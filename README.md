# nextcloud-docker
My docker compose and other things for my Nextcloud setup.

This is run behind a reverse proxy using Nginx Proxy Manager (npm), the compose file for which is not shown here.
There is minimal setup needed to get npm up and the external networks created so npm and Nextcloud are on the same networks.

In npm, under Advanced, I have the following additional configs:
```
location /.well-known/carddav {
    return 301 $scheme://$host/remote.php/dav;
}

location /.well-known/caldav {
    return 301 $scheme://$host/remote.php/dav;
}

# these webfinger and nodeinfo things might not fix the "issues"
# but I think it's a bug that it shows up as an "issue" according to:
# https://github.com/nextcloud/server/issues/25753
location = /.well-known/webfinger {
return 301 $scheme://$host:$server_port/index.php/.well-known/webfinger;
}
location = /.well-known/nodeinfo {
return 301 $scheme://$host:$server_port/index.php/.well-known/nodeinfo;
}
```

Before runing `docker-compose up -d` or the like, you will have to fill in the empty or placeholder passwords, domains, etc.
If you wish to use zfs, you will also need to create pool(s) and datasets.

Finally, after running `docker-compose up -d` run `./before_install.sh` to get folder permisisons right and remove some junk in the Nextcloud skeleton directory.
Once done, install in the browser like normal, then run `./post_first_up.sh` to automatically set much of the configuraiton. Final touch is to set the email smtp settings in the web interface (I don't like putting those settings in a .env).

I banged out the image_rename.sh in a few days and set it up with the [Workflow Scripts](https://apps.nextcloud.com/apps/workflow_script) app. That script is the part of this repo that is most likely to change at this point, and it is very much tailored to my use case.
