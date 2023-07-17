# Authentik - Bare Metal Install
This is a repository of install scripts for [Authentik](https://goauthentik.io) ([Github](https://github.com/goauthentik/authentik)) to allow for it to be installed on any ordinary bare metal host or LXC container.

Inspired by https://github.com/gtsatsis/authentik-bare-metal

 - This does **not** install, nor configure Postgres or Redis. Once they're set up, set the configuration values in `/etc/authentik/config.yml`.
 - This installs the `main` branch without a tag.
 - Python is **installed from source**, as the packages for 3.11 are missing from the Debian repositories.
 - **This setup is fully unsupported, and has no fallbacks if any step fails.**
