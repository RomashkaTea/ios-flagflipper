# Vendored Lara components

This directory contains the minimum exploit sources and two linked libraries needed by FlagFlipper, copied from [rooootdev/lara](https://github.com/rooootdev/lara) commit `879e3fae0822776d1f75f91d9f2d1aee505f339e`.

FlagFlipper removes Lara's launchd KRW handoff and recovery code from
`kexploit/darksword.m`. The persistence header and implementation are not
included, and no persistence preference or compile-time switch remains. The
kernel-access path used for the current app process is otherwise unchanged.

Lara is distributed under AGPL-3.0; the full license is in the repository root. The prebuilt `libxpf.dylib` and `libgrabkernel2.dylib` are the copies shipped with the pinned Lara commit. The original project and its notices remain available at the upstream URL above.

| Vendored library | SHA-256 |
| --- | --- |
| `libxpf.dylib` | `e87d0469bc542e1403531cf7d4f027335d514882c78b5a80cb750c5e6f310a30` |
| `libgrabkernel2.dylib` | `fb27032f7a9401b52ba94821de301aa2a57e3f61fc67bf464db3ce4075b52a4e` |
