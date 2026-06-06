FROM python:3.11-alpine AS builder
WORKDIR /app
RUN python -m venv /venv
ENV PATH="/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.11-alpine
RUN addgroup -S appgroup && adduser -S -G appgroup -H -s /sbin/nologin appuser
WORKDIR /app
COPY --from=builder --chown=appuser:appgroup /venv /venv
COPY --chown=appuser:appgroup . .
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PATH="/venv/bin:$PATH"
USER appuser
EXPOSE 8002
HEALTHCHECK --interval=10s --timeout=5s --retries=3 CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8002/health')" || exit 1
CMD ["gunicorn", "--bind", "0.0.0.0:8002", "--workers", "2", "app:app"]
