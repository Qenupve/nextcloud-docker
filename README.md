# nextcloud-docker
My docker compose and other things for my Nextcloud setup.

This is run behind a reverse proxy using Nginx Proxy Manager (npm), the compose file for which is not shown here.
There is minimal setup needed to get npm up and the external networks created so npm and Nextcloud are on the same networks.

## It's always DNS
I want to support IPv6 as natively as possible, so I edited my `/etc/docker/daemon.conf` accordingly. But that caused more problems than I cared to deal with for now...

I was originally using container names when forwarding traffic, but the docker embedded DNS doesn't have an IPv6 address (see this [feature request](https://github.com/moby/moby/issues/41651)),
so the resolver was making hostname lookups with Docker's embedded IPv4 DNS server and my hosts IPv6 DNS server in parallel,
which caused sporadic not found errors. At first I set up a firewall rule to block all IPv6 traffic on port 53 (DNS lookups) for the interface created by docker,
but the unnecessary (dropped) queries didn't sit well with me, so I switched to directly forwarding traffic to statically assigned IPv4 addresses of containers.

I have since decided to just set my local DNS server IPv4 address in the `daemon.conf`, and the custom docker networks I created and run my containers on still have IPv6 capabilities,
but they don't get the local DNS server's IPv6 address in their /etc/resolv.conf. So they use the internal Docker DNS with IPv4 for all DNS lookups to make A and AAAA queries,
at which point they can use IPv6 for the actual communication if they would like.

## Additional configuration on the reverse proxy
In npm, under Advanced, I have the following additional configs:
```
client_body_buffer_size    64M;
client_max_body_size       0;
client_body_timeout        300s;

location /.well-known/carddav {
    return 301 $scheme://$host/remote.php/dav;
}

location /.well-known/caldav {
    return 301 $scheme://$host/remote.php/dav;
}

# these webfinger and nodeinfo things don't seem to fix the "issues"
# but I think it's a bug that it shows up as an "issue" according to:
# https://github.com/nextcloud/server/issues/25753
location = /.well-known/webfinger {
return 301 $scheme://$host:$server_port/index.php/.well-known/webfinger;
}
location = /.well-known/nodeinfo {
return 301 $scheme://$host:$server_port/index.php/.well-known/nodeinfo;
}

# high performance backend notify_push service
location ^~ /push/ {
    #proxy_pass http://172.20.0.110:7867/;
    proxy_pass http://nc_notify_push.frontend:7867/;
# is this necessary?
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

## Additional other configuration
Before runing `docker-compose up -d` or the like, you will have to fill in the empty or placeholder passwords, domains, etc. You can find them all with a quick `grep -r CHANGEME`.
If you wish to use zfs, you will also need to create pool(s) and datasets.

Finally, after running `docker-compose up -d` run `./before_install.sh` to get folder permisisons right and remove some junk in the Nextcloud skeleton directory.
Once done, install in the browser like normal, then run `./post_first_up.sh` to automatically set much of the configuraiton.
Final touch is to set the email smtp settings in the web interface (I don't like putting those settings in a .env).

I banged out the image_rename.sh in a few days and set it up with the [Workflow Scripts](https://apps.nextcloud.com/apps/workflow_script) app.
That script is the part of this repo that is most likely to change at this point aside from version upbrades, and it is very much tailored to my use case.

