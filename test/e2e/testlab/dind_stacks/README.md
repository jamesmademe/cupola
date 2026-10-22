# Gli stack del dind

Tre compose che `dockge_lab.py` scrive in Dockge con `saveStack` e di cui
risponde lo scenario `dockge-lab`. Non sono servizi del compose tracciato:
Dockge li riceve come testo, li scrive in
`$CUPOLA_TESTLAB_STATE_DIR/stacks/<nome>/compose.yaml` e da lì li gestisce.

- `cupola-log.yaml`: un container che scrive una riga al secondo, così il
  terminale combinato (`docker compose logs -f`) ha qualcosa da mostrare.
- `cupola-idle.yaml`: un container che dorme, mai avviato: lo stack resta
  `Inactive` finché non lo si avvia.
- `cupola-crash.yaml`: un container che scrive una riga ed esce con 1: la lista
  di Dockge lo legge `Stopped`.

## L'immagine

`cupola-lab/base:1` è il nome dell'immagine dentro il dind. Non viene da un
registro: `dockge_lab.py` copia `alpine/socat:1.8.0.3` (10 MB, solo `/bin/sh`)
dal Docker del Mac al volume del dind con `docker save` e `docker load`, e la
ritarghetta. Da quel momento il dind non deve scaricare niente, e ogni compose
porta `pull_policy: never`: anche `Update`, che è `docker compose pull`, risponde
`Skipped` e resta offline.

Lo script è idempotente: se l'immagine c'è già non la ricarica, e il teardown
toglie quello che ha aggiunto lui (il nome `cupola-lab/base:1` e, quando non
c'era già, il tag di partenza), così il dind torna com'era.

## Il limite noto del dind

Il compose del lab monta `/var/lib/docker` del dind su una cartella dello stato
sul Mac. Quell'upperdir non regge overlayfs: il kernel monta lo snapshot in sola
lettura (`overlayfs: failed to create directory .../work/work (errno: 13)`), e
`docker run` fallisce con

```
mount callback failed on /tmp/containerd-mount…: mkdir /tmp/containerd-mount…/dev/shm: read-only file system
```

Quindi, con lo stato attuale del lab, Dockge non può creare container: ogni
stack resta `Inactive`; `Start` e `Deploy`, gli unici due che ne creerebbero
uno, rispondono `Failed to …, please check the terminal output for more
information.`, mentre `Stop`, `Restart`, `Update` e `Down` rispondono come
no-op. Lo scenario lo misura e lo scrive nel marcatore; l'e2e legge quel
valore e verifica il ramo che vale, invece di fingere uno stato che il dind non
raggiunge. Il rimedio è nel compose (un volume nominato invece del bind mount),
fuori dai file di questo lotto.

La coda del messaggio cambia con il passo che il kernel non riesce a scrivere
(`mkdir …/dev/shm: read-only file system`, `mkdir …/dev/pts: read-only file
system`, `open …/dev/console: read-only file system`, `symlink …/etc/mtab: file
exists`); la frase stabile è `mount callback failed`, ed è quella che le prove
asseriscono.
