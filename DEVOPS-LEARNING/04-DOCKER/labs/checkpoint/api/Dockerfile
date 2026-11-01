FROM python:3.12-slim

WORKDIR /app
COPY . .

RUN useradd --system --uid 10001 --no-create-home reporter
USER reporter

EXPOSE 8000
CMD ["python", "app.py"]
