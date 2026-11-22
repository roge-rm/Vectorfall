FROM python:3.13-slim-trixie AS build
ARG GODOT_VERSION=4.7.2
RUN python3 - <<'FETCH'
import os
from pathlib import Path
import shutil
from urllib.request import urlopen
from zipfile import ZipFile

version = os.environ["GODOT_VERSION"]
name = f"Godot_v{version}-stable_linux.x86_64"
url = f"https://github.com/godotengine/godot/releases/download/{version}-stable/{name}.zip"
archive = Path("/tmp/godot.zip")
with urlopen(url, timeout=60) as response, archive.open("wb") as output:
    shutil.copyfileobj(response, output)
binary = Path("/usr/local/bin/godot")
with ZipFile(archive) as files, files.open(name) as source, binary.open("wb") as output:
    shutil.copyfileobj(source, output)
binary.chmod(0o755)
archive.unlink()
FETCH
WORKDIR /src
COPY . .
RUN mkdir /out \
    && godot --headless --import > /tmp/import.log 2>&1 \
    && ! grep -q 'SCRIPT ERROR' /tmp/import.log \
    && godot --headless --export-pack Linux /out/vectorfall.pck > /tmp/export.log 2>&1 \
    && test -s /out/vectorfall.pck \
    && cp /usr/local/bin/godot /out/godot \
    || (cat /tmp/import.log /tmp/export.log; exit 1)

FROM debian:trixie-slim
RUN install -d -o 10003 -g 10003 /state /opt/vectorfall
COPY --from=build /out/ /opt/vectorfall/
ENV XDG_DATA_HOME=/state XDG_CONFIG_HOME=/state XDG_CACHE_HOME=/state VECTORFALL_STATUS_DIR=/state GODOT_SILENCE_ROOT_WARNING=1
USER 10003:10003
EXPOSE 27300/udp 27301/udp 27302/tcp
ENTRYPOINT ["/opt/vectorfall/godot", "--headless", "--main-pack", "/opt/vectorfall/vectorfall.pck", "res://scenes/server.tscn"]
