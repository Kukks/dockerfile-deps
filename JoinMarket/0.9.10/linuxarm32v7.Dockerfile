FROM debian:bookworm-slim as builder
RUN apt-get update && apt-get install -qq --no-install-recommends qemu-user-static

# We use a prebuilt image, because our builder on circleci timeout after 1H and the build take too long
FROM builder as cryptographybuilder
RUN apt-get install -qq --no-install-recommends wget
ENV CRYPTO_TAR="cryptography-3.3.2-pip-arm32v7.tar"
RUN mkdir -p /root/.cache && cd /root/.cache && \
    wget -qO ${CRYPTO_TAR} "http://aois.blob.core.windows.net/public/${CRYPTO_TAR}" && \
    echo "c7dde603057aaa0cb35582dba59ad487262e7f562640867545b1960afaf4f2e4 ${CRYPTO_TAR}" | sha256sum -c - && \
    tar -xvf "${CRYPTO_TAR}" && \
    rm "${CRYPTO_TAR}"

FROM arm32v7/python:3.9-slim-bookworm

COPY --from=builder /usr/bin/qemu-arm-static /usr/bin/qemu-arm-static
COPY --from=cryptographybuilder /root/.cache /root/.cache

ENV REPO https://github.com/JoinMarket-Org/joinmarket-clientserver
ENV REPO_REF v0.9.10

ENV DATADIR /root/.joinmarket
ENV CONFIG ${DATADIR}/joinmarket.cfg
ENV DEFAULT_CONFIG /root/default.cfg
ENV DEFAULT_AUTO_START /root/autostart
ENV AUTO_START ${DATADIR}/autostart
ENV ENV_FILE "${DATADIR}/.env"

# install dependencies
RUN apt-get update
RUN apt-get install -qq --no-install-recommends curl tini procps vim git iproute2 gnupg supervisor \
    build-essential automake pkg-config libtool libffi-dev libssl-dev libgmp-dev libltdl-dev libsodium-dev \
    python3-dev python3-pip python3-setuptools python3-venv

# install joinmarket
WORKDIR /src
RUN git clone "$REPO" . --depth=1 --branch "$REPO_REF" && git checkout "$REPO_REF"
RUN ./install.sh --docker-install --without-qt
RUN pip install matplotlib

# setup
WORKDIR /src/scripts
RUN (python wallet-tool.py generate || true) && cp "${CONFIG}" "${DEFAULT_CONFIG}"
COPY *.sh ./
COPY autostart /root/
COPY supervisor-conf/*.conf /etc/supervisor/conf.d/
ENV PATH /src/scripts:$PATH

# cleanup and remove ephemeral dependencies
RUN rm --recursive --force install.sh deps/cache/ test/ .git/ .gitignore .github/ .coveragerc joinmarket-qt.desktop
RUN apt-get remove --purge --auto-remove -y gnupg python3-pip apt-transport-https && apt-get clean
RUN rm -rf /var/lib/apt/lists/* /var/log/dpkg.log

# jmwallet daemon
EXPOSE 28183
# payjoin server
EXPOSE 8080
# obwatch
EXPOSE 62601
ENTRYPOINT  [ "tini", "-g", "--", "./docker-entrypoint.sh" ]
