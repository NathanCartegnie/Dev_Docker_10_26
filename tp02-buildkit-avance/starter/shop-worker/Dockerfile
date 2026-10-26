FROM python:3.12 AS builder
WORKDIR /app

COPY requirements.txt ./
RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf \
    --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip && \
    pip install --prefix=/install -r requirements.txt

FROM python:3.12 AS test
WORKDIR /app

COPY --from=builder /install /usr/local
COPY requirements-dev.txt requirements.txt ./
COPY worker ./worker
COPY tests ./tests
RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf \
    --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements-dev.txt && \
    pytest -q

FROM python:3.12 AS runtime
WORKDIR /app

COPY --from=builder /install /usr/local
COPY worker ./worker
ENV PYTHONUNBUFFERED=1
CMD ["python", "-m", "worker.main"]
