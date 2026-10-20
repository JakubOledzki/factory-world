# Built in CI after the Godot web export has been written to client/build/web.
FROM caddy:2
COPY client/build/web /srv
COPY deploy/Caddyfile /etc/caddy/Caddyfile
