# ─── Stage 1: build ───────────────────────────────────────────────────────────
# mono-complete + imagemagick are only needed here.
# Neither is carried into the runtime image.
FROM debian:12-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
        mono-complete \
        imagemagick \
    && rm -rf /var/lib/apt/lists/*

COPY HelloWorld.cs /build/HelloWorld.cs
RUN mcs \
        -r:System.Windows.Forms.dll \
        -r:System.Drawing.dll \
        /build/HelloWorld.cs \
        -out:/build/HelloWorld.exe

# Generate desktop icons — build stage only, not carried into runtime image
RUN convert \
        -size 48x48 xc:"#1565C0" \
        -fill white -font DejaVu-Sans-Bold -pointsize 16 \
        -gravity center -annotate 0 "HW" \
        /build/kiosk-icon.png \
    && convert \
        -size 48x48 xc:"#1B5E20" \
        -fill white -font DejaVu-Sans-Bold -pointsize 14 \
        -gravity center -annotate 0 ">_" \
        /build/terminal-icon.png \
    && convert \
        -size 48x48 xc:"#B8860B" \
        -fill white -font DejaVu-Sans-Bold -pointsize 12 \
        -gravity center -annotate 0 "DOS" \
        /build/dosbox-icon.png

# ─── Stage 2: runtime ─────────────────────────────────────────────────────────
FROM debian:12-slim AS runtime

ARG KIOSK_USER=kioskuser
ENV KIOSK_USER=${KIOSK_USER}
ENV KIOSK_PASS=changeme

# ─── Stable packages ──────────────────────────────────────────────────────────
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
        \
        # Desktop icon renderer
        idesk \
        \
        # Lightweight terminal + process monitor
        xterm \
        procps \
    && rm -rf /var/lib/apt/lists/*

# ─── DOSBox-X from Debian trixie (not in bookworm stable) ────────────────────
# Pin trixie at low priority so only the explicitly requested package
# is pulled from testing; everything else stays on bookworm.
RUN echo "deb http://deb.debian.org/debian trixie main" \
        > /etc/apt/sources.list.d/trixie.list \
    && printf 'Package: *\nPin: release n=trixie\nPin-Priority: 100\n\nPackage: dosbox-x\nPin: release n=trixie\nPin-Priority: 900\n' \
        > /etc/apt/preferences.d/trixie \
    && apt-get update \
    && apt-get install -y --no-install-recommends dosbox-x \
    && rm /etc/apt/sources.list.d/trixie.list \
    && rm /etc/apt/preferences.d/trixie \
    && rm -rf /var/lib/apt/lists/*

# ─── Kiosk user (password set at runtime by entrypoint) ──────────────────────
RUN useradd -m -s /bin/bash "${KIOSK_USER}" \
    && usermod -aG ssl-cert "${KIOSK_USER}"

# ─── Copy compiled binary and icons from build stage ─────────────────────────
COPY --from=build --chown=${KIOSK_USER}:${KIOSK_USER} /build/HelloWorld.exe \
     /home/${KIOSK_USER}/HelloWorld.exe
RUN chmod 0755 "/home/${KIOSK_USER}/HelloWorld.exe"

RUN mkdir -p "/home/${KIOSK_USER}/.idesktop/icons"
COPY --from=build /build/kiosk-icon.png \
     /home/${KIOSK_USER}/.idesktop/icons/kiosk-icon.png
COPY --from=build /build/terminal-icon.png \
     /home/${KIOSK_USER}/.idesktop/icons/terminal-icon.png
COPY --from=build /build/dosbox-icon.png \
     /home/${KIOSK_USER}/.idesktop/icons/dosbox-icon.png

# ─── iDesk icon configs ───────────────────────────────────────────────────────
COPY --chown=${KIOSK_USER}:${KIOSK_USER} HelloWorld.lnk \
     /home/${KIOSK_USER}/.idesktop/HelloWorld.lnk
COPY --chown=${KIOSK_USER}:${KIOSK_USER} Terminal.lnk \
     /home/${KIOSK_USER}/.idesktop/Terminal.lnk
COPY --chown=${KIOSK_USER}:${KIOSK_USER} DOSBox.lnk \
     /home/${KIOSK_USER}/.idesktop/DOSBox.lnk
RUN chown -R "${KIOSK_USER}:${KIOSK_USER}" "/home/${KIOSK_USER}/.idesktop"

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
