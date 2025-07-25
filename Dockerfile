FROM python:3.11-slim
RUN useradd -m appuser
WORKDIR /home/appuser
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/app.py .
EXPOSE 8080 9090
HEALTHCHECK --interval=15s --timeout=3s \
 CMD curl --fail http://localhost:8080/health || exit 1
USER appuser
CMD ["sh","-c","python -m prometheus_client --bind 0.0.0.0:9090 & python app.py"]