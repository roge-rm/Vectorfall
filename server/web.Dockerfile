FROM python:3.13-slim-trixie
RUN install -d -o 10003 -g 10003 /state
WORKDIR /opt/skifrei
COPY server/web/ art/fonts/BigShouldersDisplay-Black.ttf art/fonts/IBMPlexSerif-Medium.ttf art/fonts/*-OFL.txt art/icon.png web/
USER 10003:10003
ENV SKIFREI_STATUS_DIR=/state SKIFREI_PLAY_DIR=/play
ENTRYPOINT ["python3", "web/admin.py"]
