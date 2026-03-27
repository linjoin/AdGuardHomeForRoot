 # AdGuardHome for Root AutoOpt

[简体中文](README.md) | English

![arm-64 support](https://img.shields.io/badge/arm--64-support-ef476f?logo=linux&logoColor=white&color=ef476f)
![arm-v7 support](https://img.shields.io/badge/arm--v7-support-ffa500?logo=linux&logoColor=white&color=ffa500)
![License](https://img.shields.io/badge/License-MIT-9b5de5?logo=opensourceinitiative&logoColor=white)
[![Docs](https://img.shields.io/badge/Docs-Guide-0066ff?logo=book&logoColor=white)](docs/index.md)
[![Join Telegram Channel](https://img.shields.io/badge/Telegram-Join%20Channel-06d6a0?logo=telegram&logoColor=white)](https://t.me/+jMhOKwFEgwxlOTA1)
[![Join Telegram Group](https://img.shields.io/badge/Telegram-Join%20Group-118ab2?logo=telegram&logoColor=white)](https://t.me/vrIbVug1CRMzY2I1)
[![Join QQ Group](https://img.shields.io/badge/QQ-404%20Not%20Found-blue?logo=tencent-qq&logoColor=white)](https://qm.qq.com/q/A3bogqGvIe)

Follow our channel for the latest updates, or join our group for discussions! QQ Group is recommended!

## Introduction

- This module runs [AdGuardHome](https://github.com/AdguardTeam/AdGuardHome) on Android devices, providing a local DNS server capable of blocking ads, malware, and trackers.
- It can be used as a local ad-blocking module or transformed into a standalone AdGuardHome tool by adjusting the configuration file.
- Supports multiple installation methods including Magisk, KernelSU, and APatch, compatible with most Android devices.
- Designed to provide a lightweight ad-blocking solution without the complexity and performance overhead of VPN-based methods.
- Can coexist with other proxy software (such as [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid), [FlClash](https://github.com/chen08209/FlClash), [box for magisk](https://github.com/taamarin/box_for_magisk), [akashaProxy](https://github.com/akashaProxy/akashaProxy), etc.) for enhanced privacy protection and network security.

## Features

- Optional forwarding of local DNS requests to the local AdGuardHome server
- Automatic architecture detection and module selection from the compressed package
- And many more features — install and experience them yourself!
- Blacklists: [GOODBYEADS](https://ghfast.top/raw.githubusercontent.com/8680/GOODBYEADS/master/data/rules/dns.txt), [Blacklist_for_AdGuardHome](https://github.com/linjoin/Blacklist_for_AdGuardHome), [AdGuard Rule](https://mirror.ghproxy.com/https://raw.githubusercontent.com/zimoadmin/adgrule/main/rule/adgh.txt)
- Whitelists: [GOODBYEADS](https://ghfast.top/raw.githubusercontent.com/8680/GOODBYEADS/master/data/rules/allow.txt), [Whitelist_for_AdGuardHome](https://raw.githubusercontent.com/linjoin/Whitelist_for_AdGuardHome/refs/heads/main/whitelist.txt)

- Access the AdGuardHome dashboard at <http://127.0.0.1:3000>, supporting query statistics, modifying DNS upstream servers, and custom rules

## Tutorial

1. Download the module from the [Release](https://github.com/linjoin/AdGuardHomeForRoot/releases) page
2. Check Android Settings -> Network & Internet -> Advanced -> Private DNS, ensure `Private DNS` is turned OFF
3. Install the module in your root manager and reboot the device
4. If you see the module running successfully notification, access <http://127.0.0.1:3000> to enter the AdGuardHome dashboard. Default credentials: root/root
5. For advanced usage tutorials and FAQ, please visit **[Documentation & Tutorials](docs/index.md)**.
