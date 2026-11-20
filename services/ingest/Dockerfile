# Build from the repository root:
#   docker build --platform linux/amd64 -f services/ingest/Dockerfile -t <ecr-url>:<tag> .
FROM public.ecr.aws/lambda/python:3.13

COPY services/ingest/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

COPY services/shared/rag_shared ${LAMBDA_TASK_ROOT}/rag_shared
COPY services/ingest/app ${LAMBDA_TASK_ROOT}/app

CMD ["app.handler.lambda_handler"]
