FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE 1 \
    PYTHONUNBUFFERED 1

RUN pip install --upgrade --no-cache-dir black
RUN apt-get update
RUN apt-get install --no-install-recommends -y git jq curl

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
