FROM python:3.13-slim-trixie
RUN install -d -o 10003 -g 10003 /state
WORKDIR /opt/vectorfall
COPY server/web/ art/fonts/BigShouldersDisplay-Black.ttf art/fonts/IBMPlexSerif-Medium.ttf art/fonts/*-OFL.txt art/icon.svg web/
USER 10003:10003
ENV VECTORFALL_STATUS_DIR=/state VECTORFALL_PLAY_DIR=/play
ENTRYPOINT ["python3", "web/admin.py"]
