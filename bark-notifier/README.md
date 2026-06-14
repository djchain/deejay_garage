# Bark Notifier

Lightweight local notification component for sending Mac work updates to Deejay's iPhone through Bark.

## Runtime

- CLI command: `/Users/deejay/.local/bin/bark`
- Private config: `/Users/deejay/.config/bark/bark.env`
- Reusable shell functions: `notify.sh`

The Bark device key stays in the private config file and should not be copied into this repo, logs, prompts, or public code.

## Direct Use

```sh
bark "Task finished" "The Mac job completed."
bark -l timeSensitive "Backup failed" "Check the local backup job."
bark run -- sleep 10
```

`bark run -- <command>` runs a command, sends a success or failure notification when it exits, and returns the original command's exit status.

## Script Component

Source the component from any shell script:

```sh
. /Users/deejay/codes/garage/bark-notifier/notify.sh

bark_notify "Task finished" "Everything is ready."
bark_notify_failure "Deploy failed" "Check the terminal output."
bark_notify_run sleep 10
```

Optional defaults:

```sh
export BARK_NOTIFY_DEFAULT_LEVEL=timeSensitive
export BARK_NOTIFY_DEFAULT_GROUP=Garage
```

Levels commonly used by Bark:

- `active`
- `timeSensitive`
- `passive`
- `critical`

Use `timeSensitive` for things that should cut through more iOS noise. Reserve `critical` for genuine emergencies.
