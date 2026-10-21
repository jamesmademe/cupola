# Python 3.12.14 / Alpine 3.24, multi-arch manifest pinned by digest.
FROM python:3.12-alpine@sha256:c4634f578a412db396771b61b064c6e546c9d6414c7fb5b1b05d5871f1885f7b

WORKDIR /app
COPY server.py /app/server.py

ENV PYTHONUNBUFFERED=1
CMD ["python3", "/app/server.py"]
