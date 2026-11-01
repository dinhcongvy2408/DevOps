FROM python:3.12-slim

WORKDIR /app
COPY worker.py .

RUN useradd --system --uid 10002 --no-create-home worker
USER worker

CMD ["python", "-u", "worker.py"]
