# Minimal image for the demo app. The deploy/rollback scripts in this repo
# operate on the symlink+releases pattern (see README) rather than driving
# `docker run` directly, so this image is what the CI workflow builds and
# pushes — the actual deploy mechanics are container-runtime-agnostic and
# would work the same way driving `docker run`/`docker stop` instead.
FROM python:3.12-alpine
WORKDIR /app
COPY app/app.py .
EXPOSE 8080
ENTRYPOINT ["python3", "app.py", "8080"]
