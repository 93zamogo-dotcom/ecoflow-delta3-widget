FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY ecoflow_client.py server.py ./

ENV BRIDGE_HOST=0.0.0.0
ENV BRIDGE_PORT=8080
ENV ECOFLOW_REGION=eu

EXPOSE 8080

CMD ["python", "server.py"]
