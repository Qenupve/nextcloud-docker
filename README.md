# nextcloud-docker
My docker compose and other things for my Nextcloud setup.

This is run behind a reverse proxy using Nginx Proxy Manager (npm), the compose file for which is not shown here.
There is minimal setup needed to get npm up and the external networks created so npm and Nextcloud are on the same networks.

Before runing `docker-compose up -d` or the like, you will have to fill in some placeholder passwords, domains, etc.
If you wish to use zfs, you will also need to create a pool and datasets.
