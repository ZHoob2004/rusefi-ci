# rusefi-ci

This dockerfile will automatically download and configure the github actions self-hosted runner

To run, first build the image with:

`docker build --build-arg GID=$(getent group docker | cut -d ':' -f 3) -t rusefi-ci .`

Then run the newly built image.

```bash
docker run --detach --privileged \
    -e RUNNER_NAME=test-runner2 \
    -e RUNNER_LABELS=ubuntu-latest \
    -e GITHUB_ACCESS_TOKEN=<Personal Access Token> \
    -e RUNNER_REPOSITORY_URL=https://github.com/<github user>/rusefi \
    rusefi-ci
```
Replace `<github user>` with your own username if you are running on your own fork.
If you are running an organization-level runner, you will need to replace `RUNNER_REPOSITORY_URL` with `RUNNER_ORGANIZATION_URL`.


Add `--restart=unless-stopped` in order to have the container survive reboots

The container uses a persistent volume mounted at /opt/actions-runner. After initial startup, the container will skip registration unless the peristent volume is erased.

## Environment variables

The following environment variables allows you to control the configuration parameters.

| Name | Description | Required/Default value |
|------|---------------|-------------|
| RUNNER_REPOSITORY_URL | The runner will be linked to this repository URL | Required if `RUNNER_ORGANIZATION_URL` is not provided |
| RUNNER_ORGANIZATION_URL | The runner will be linked to this organization URL. *(Self-hosted runners API for organizations is currently in public beta and subject to changes)* | Required if `RUNNER_REPOSITORY_URL` is not provided |
| GITHUB_ACCESS_TOKEN | Personal Access Token. Used to dynamically fetch a new runner token (recommended, see below). | Required if `RUNNER_TOKEN` is not provided.
| RUNNER_TOKEN | Runner token provided by GitHub in the Actions page. These tokens are valid for a short period. | Required if `GITHUB_ACCESS_TOKEN` is not provided
| RUNNER_WORK_DIRECTORY | Runner's work directory | `"_work"`
| RUNNER_NAME | Name of the runner displayed in the GitHub UI | Hostname of the container
| RUNNER_LABELS | Extra labels in addition to the default: 'self-hosted,Linux,X64' (based on your OS and architecture) | `""`
| RUNNER_REPLACE_EXISTING | `"true"` will replace existing runner with the same name, `"false"` will use a random name if there is conflict | `"true"`

## Runner Token

In order to link your runner to your repository/organization, you need to provide a token. There is two way of passing the token :

* via `GITHUB_ACCESS_TOKEN` (recommended), containing a [fine-grained Personnal Access Token](https://github.com/settings/tokens). This token will be used to dynamically fetch a new runner token, as runner tokens are valid for a short period of time.
  * For a single-repository runner, select the repository under "Only select repositories", then under "Repository Permissions" set "Administration" to read-write.
  * For an organization runner, select the repository and set "Organization self hosted runners"to read-write.
* via `RUNNER_TOKEN`. This token is displayed in the Actions settings page of your organization/repository, when opening the "Add Runner" page.

## Helper Functions

If you stop and start workes often, you may find it useful to have a function for starting workers. I have added the below functions to my .bashrc:

```bash
ghatoken ()
{
 echo -n "Paste token:"
 read TOKEN
 KEY=$(echo "$TOKEN" | openssl enc -aes-256-cbc -a -pbkdf2 | tr -d '\n')
 perl -pi -e 's#(?<=TOKEN=\$\(echo\s").*?(?="\s\|)#'"$KEY"'#' $(realpath ~/.bashrc)
 bash
}

gha ()
{
  if ! TOKEN=$(echo "" | openssl enc -aes-256-cbc -a -d -pbkdf2 ); then echo "Error encoding token"; return 1; fi
  NAME="runner-$1"
  LABEL=${2:-"ubuntu-latest"}
  IMAGE_HASH=$(docker image inspect rusefi-ci --format "{{.Id}}" 2>/dev/null)
  if CONTAINER_HASH=$(docker container inspect $NAME --format "{{.Image}}" 2>/dev/null) && [ "$IMAGE_HASH" = "$CONTAINER_HASH" ]; then
    docker start -i "$NAME"
  else
    if docker container inspect "$NAME" >/dev/null 2>/dev/null; then
      docker rm "$NAME"
    fi
    if [ -n "$3" ]; then
      MOUNT="-v $PWD/$3:/opt/actions-runner/rusefi-env:ro"
    fi
    docker run -it --privileged $MOUNT -e RUNNER_NAME="$NAME" -e RUNNER_LABELS="$LABEL" -e GITHUB_ACCESS_TOKEN="$TOKEN" -e RUNNER_REPOSITORY_URL=https://github.com/chuckwagoncomputing/rusefi --name $NAME rusefi-ci
  fi
}
```

Replace `<github user>` with your own username if you are running on your own fork.
If you are running an organization-level runner, you will need to replace `RUNNER_REPOSITORY_URL` with `RUNNER_ORGANIZATION_URL`.

Once the functions are in your .bashrc, and you have sourced your .bashrc, by opening a new shell or by running `. ~/.bashrc`,
run `ghatoken`, paste in your PAT, and enter a password. This password will be used every time you start a runner.

After you have run `ghatoken`, you can now start runners with `gha <id>`. I use sequential ids, e.g. `gha 1`, `gha 2`, etc,
but you may name them however you like. You can also pass a label, or multiple labels separated with a comma, as the second option. If omitted, `ubuntu-latest` will be used.

Note that these helper functions start the runner in interactive mode. If you prefer, you can remove the `-i` in `docker start -i` and replace the `-it` in `docker run -it` with `--detach`.

## Hardware CI

### udev Rules

_Assuming your host is Linux_

On your host machine, you need to make your board and ST-Link owned by the docker group.
Place this in /etc/udev/rules.d/70-rusefi.rules, replacing the serials with those of your board and ST-Link respectively.
```
SUBSYSTEM=="tty", ATTRS{serial}=="24001D001247393338343537", GROUP="docker"
SUBSYSTEM=="usb", ATTRS{serial}=="066CFF3834344E5043242446", GROUP="docker"
```

### Configuring Runner

Prepare a file with the serial numbers of your hardware, like this one:
```
HARDWARE_CI_SERIAL=24001D001247393338343537
HARDWARE_CI_STLINK_SERIAL=066CFF3834344E5043242446
HARDWARE_CI_VBATT=12
```

Now when you first create your runner, you can pass this file as the third option on the command line.  
`gha f407-discovery hw-ci-f4-discovery rusefi-env`
