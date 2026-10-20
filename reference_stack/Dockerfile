FROM python:3.12-alpine
WORKDIR /app
COPY service.py .
ENV PORT=8000
EXPOSE 8000
USER nobody
CMD ["python", "-u", "service.py"]
