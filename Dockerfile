# ─── Stage 1: build ───────────────────────────────────────────────────────────
# mono-complete is only needed here to compile the .cs source.
# It is NOT carried into the runtime image.
FROM debian:12-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
        mono-complete \
    && rm -rf /var/lib/apt/lists/*

COPY HelloWorld.cs /build/HelloWorld.cs
RUN mcs \
        -r:System.Windows.Forms.dll \
        -r:System.Drawing.dll \
        /build/HelloWorld.cs \
        -out:/build/HelloWorld.exe

# ─── Stage 2: runtime ─────────────────────────────────────────────────────────
# Only the packages actually needed to *run* a WinForms app over RDP.
FROM debian:12-slim AS runtime

ARG KIOSK_USER=kioskuser
ENV KIOSK_USER=${KIOSK_USER}
ENV KIOSK_PASS=changeme

RUN apt-get update && apt-get install -y --no-install-recommends \
        \
        # Display / RDP stack
        xserver-xorg-core \
        xserver-xorg \
        xorgxrdp \
        xinit \
        openbox \
        xrdp \
        \
        # Mono runtime — no compiler, no debugger, no MSBuild
        mono-runtime \
        libmono-system-windows-forms4.0-cil \
        libmono-system-drawing4.0-cil \
        libmono-system4.0-cil \
        libgdiplus \
    && rm -rf /var/lib/apt/lists/*

# ─── Kiosk user (password set at runtime by entrypoint) ──────────────────────
RUN useradd -m -s /bin/bash "${KIOSK_USER}" \
    && usermod -aG ssl-cert "${KIOSK_USER}"

# ─── Copy compiled binary from build stage ────────────────────────────────────
COPY --from=build --chown=${KIOSK_USER}:${KIOSK_USER} /build/HelloWorld.exe \
     /home/${KIOSK_USER}/HelloWorld.exe
RUN chmod 0755 "/home/${KIOSK_USER}/HelloWorld.exe"

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
