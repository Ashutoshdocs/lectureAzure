FROM python:3.12-slim

# Version is baked into the image at build time (v1 / v2) for the rollout demo
ARG APP_VERSION=v1
ENV APP_VERSION=${APP_VERSION} \
    PYTHONUNBUFFERED=1 \
    PORT=8000

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

EXPOSE 8000
# 2 workers x 8 threads per container; enough to show concurrency limits per instance
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--threads", "8", "--timeout", "60", "app:app"]
