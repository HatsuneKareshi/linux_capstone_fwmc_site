# What is this
This is a tiny repo for a capstone project for a Linux course. The site we built is an almost one to one copy of https://fwmcbaubau.com/, since it is simple enough whilst still necessitating the usage of a database, in this case PostgreSQL packaged in a Docker container. 

# If for some reason you want to run this instead of just using the actual https://fwmcbaubau.com/ site

You will need 2 seperate ENVs:

An `.env` file. This one is for the `main.py` application to use, it should look something like
```env
DATABASE_URL=postgresql://<usr>:<psw>@<IP/DNS whatevers>:<port>/baubau_db
```
> With the user here being less priveleged. It is set in init.sh, change that to whatever you want, or dont if you like Mocochan.

And an `.env.db`. This one is for the docker postgreSQL itself, which should look like
```
POSTGRES_USER=<priv'd user>
POSTGRES_PASSWORD=<password>
POSTGRES_DB=baubau_db
APP_USER=<user>
APP_PASSWORD=<psw>
```

> The db here is named `baubau_db`. This user here is needed to run initial setup (thats the `init.sh`), and to set up `mocochan` as the least privileged user.

, and be placed at the same directory as the `main.py`, the `*compose.yaml` files, or otherwise specify the path of the environment file specifically. Set your own database user, its password and db IP/host.

Check out the `compose.yaml` if you want to build the images as the code stands in the repository, and then run both. `compose-remote.yaml` will grab both images from my dockerhub, `ci-bot-minhminhchan`. 

For our capstone we can only run just the `dbonly_compose.yaml`, as the python application has to be run by systemd and not by docker itself, for auto startup, logging, etc...