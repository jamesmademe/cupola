# Python 3.12 slim, pinned; ffmpeg and mktorrent make the synthetic release.
FROM python:3.12-slim@sha256:cb33f7f771ecec2ef1225cf39b159591a040391bd73e4c01f00fdfc4c47611d2

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg mktorrent \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY forge.py /app/forge.py
ENV PYTHONUNBUFFERED=1
ENTRYPOINT ["python3", "/app/forge.py"]
