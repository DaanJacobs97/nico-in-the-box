# Nico Caster

A separate app that turns a device into the **shared screen** for a Nico in the Box room. It runs on Windows,
Android and Android TV (it appears in the TV launcher), with iOS as an untested stub.

## How it works

1. Start the Caster on the device connected to the TV. It shows **Waiting for a host**, its name and its address.
2. In Nico in the Box, the host turns on *Single game screen*, chooses *Caster app* and picks this screen from the
   list. Hosts can also type the address shown, as a fallback.
3. The Caster shows the room's lobby, then the game table and results. Players only see their own hand and buttons.
4. When the host closes the room or disconnects, the Caster returns to waiting.

A Caster shows one room at a time. Other hosts see it as *In use* and are refused with a "busy" message. The screen
stays awake and in landscape. Tap the pencil to rename it; the name is remembered.

## Network

| Port | Use |
|---|---|
| UDP 47802 | Announces this Caster every second so hosts can list it |
| TCP 47803 | WebSocket at `/cast`: the host connects, says `castHello`, then pushes `display` updates |

On Windows, allow the firewall prompt on *Private* networks the first time.

## Development

```bash
flutter run -d windows        # or an Android device / TV
flutter test
```

The screen itself is `SharedScreenView` from `packages/nico_shared`, the same widget the host app uses when the
host's device is the screen. Announcements use `RoomBroadcaster` from `packages/nico_native`.
