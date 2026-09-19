# Copy into the drjhagpt-enterprise repository root. Build:  docker build -t localhost:5111/drjhagpt-pro:dev .
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
RUN useradd -m -u 1000 app
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY --chown=app:app . .
USER app
EXPOSE 8501
# ARG so the same Dockerfile serves every Streamlit app in the family
ARG APP_FILE=streamlit_app.py
ENV APP_FILE=${APP_FILE}
CMD ["sh", "-c", "streamlit run ${APP_FILE} --server.port=8501 --server.address=0.0.0.0"]
