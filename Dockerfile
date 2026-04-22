FROM debian:12-slim

# Build-time username — used to set up home dir, files, and paths
ARG KIOSK_USER=kioskuser
ENV KIOSK_USER=${KIOSK_USER}

# Runtime password — injected via `docker run -e` or docker-compose env_file
# Default is intentionally weak; override it in production
ENV KIOSK_PASS=changeme

# ─── System packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        xserver-xorg-core \
        xserver-xorg \
        xorgxrdp \
        xinit \
        openbox \
        xrdp \
        mono-complete \
    && rm -rf /var/lib/apt/lists/*

# ─── Kiosk user (password is set at runtime by entrypoint) ───────────────────
RUN useradd -m -s /bin/bash "${KIOSK_USER}" \
    && usermod -aG ssl-cert "${KIOSK_USER}"

# ─── Compile the .NET app ─────────────────────────────────────────────────────
COPY HelloWorld.cs /tmp/HelloWorld.cs
RUN mcs \
        -r:System.Windows.Forms.dll \
        -r:System.Drawing.dll \
        /tmp/HelloWorld.cs \
        -out:/home/${KIOSK_USER}/HelloWorld.exe \
    && chown "${KIOSK_USER}:${KIOSK_USER}" "/home/${KIOSK_USER}/HelloWorld.exe" \
    && chmod 0755 "/home/${KIOSK_USER}/HelloWorld.exe" \
    && rm /tmp/HelloWorld.cs

# ─── RDP session → Openbox ────────────────────────────────────────────────────
RUN echo "exec openbox-session" > "/home/${KIOSK_USER}/.xsession" \
    && chown "${KIOSK_USER}:${KIOSK_USER}" "/home/${KIOSK_USER}/.xsession" \
    && chmod 0644 "/home/${KIOSK_USER}/.xsession"

# ─── Openbox autostart: disable blanking, launch the app ─────────────────────
RUN mkdir -p "/home/${KIOSK_USER}/.config/openbox"
COPY --chown=${KIOSK_USER}:${KIOSK_USER} openbox-autostart \
     /home/${KIOSK_USER}/.config/openbox/autostart
RUN chmod 0755 "/home/${KIOSK_USER}/.config/openbox/autostart"

# ─── Tune xrdp for low-resource / LAN use ────────────────────────────────────
RUN sed -i 's/^crypt_level=.*/crypt_level=low/'  /etc/xrdp/xrdp.ini \
    && sed -i 's/^max_bpp=.*/max_bpp=16/'        /etc/xrdp/xrdp.ini

# ─── Entrypoint ───────────────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3389

ENTRYPOINT ["/entrypoint.sh"]
