# Prebuilt firmware

The ready-to-flash images (`*.factory.bin`) are not stored in the repository.
Download them from the **Releases** page of this repository.

To make them yourself: `cd firmware && pio run -e <env>`. The image is then at
`firmware/.pio/build/<env>/firmware.factory.bin`.

| Environment | Image name |
|---|---|
| `t-dongle-s3` | `hidlink-t-dongle-s3-v<version>.factory.bin` |
| `t-dongle-s3-nolcd` | `hidlink-t-dongle-s3-nolcd-v<version>.factory.bin` |
| `t-dongle-s3-debug` | `hidlink-t-dongle-s3-debug-v<version>.factory.bin` |

Flash at address `0x0` (see the main README).
