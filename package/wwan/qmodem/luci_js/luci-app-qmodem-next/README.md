# LuCI App QModem Next

Modern JavaScript-based LuCI interface for QModem management.

## Features

- **Modern UI**: Built with LuCI's modern JavaScript framework
- **Real-time Monitoring**: Auto-refresh modem status every 5 seconds
- **Multiple Modems**: Support for multiple modem configurations
- **Comprehensive Information**: 
  - Basic modem information (Model, IMEI, Firmware, etc.)
  - Network information (Signal strength, Network type, Cell ID, etc.)
  - Cell information (Band, PCI, EARFCN, etc.)
  - SIM information (ICCID, IMSI, Phone number, etc.)
- **AT Command Interface**: Send custom AT commands with quick command shortcuts
- **Modem Control**: Soft and hard reboot options
- **Configuration Management**: Easy UCI-based configuration
- **Responsive Design**: Works on desktop and mobile devices

## Installation

```bash
# Install the package
opkg install luci-app-qmodem-next

# Restart services
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```

## Dependencies

- qmodem: Core QModem package
- luci-base: LuCI base framework
- rpcd: RPC daemon for ubus calls

## File Structure

```
luci-app-qmodem-next/
├── Makefile
├── README.md
├── htdocs/
│   └── luci-static/
│       └── resources/
│           ├── qmodem/
│           │   └── qmodem.js          # QModem API wrapper
│           └── view/
│               └── qmodem/
│                   ├── overview.js    # Overview page
│                   ├── config.js      # Configuration page
│                   ├── debug.js       # Debug/AT command page
│                   └── settings.js    # Settings page
├── root/
│   └── usr/
│       └── share/
│           ├── luci/
│           │   └── menu.d/
│           │       └── luci-app-qmodem-next.json  # Menu definition
│           └── rpcd/
│               └── acl.d/
│                   └── luci-app-qmodem-next.json  # Access control
└── po/
    └── zh_Hans/
        └── luci-app-qmodem-next.po    # Chinese translation
```

## Usage

### Accessing the Interface

1. Navigate to **Modem → QModem** in LuCI web interface
2. View modem status in the Overview page
3. Configure modems in the Configuration page
4. Send AT commands in the Debug page
5. Adjust global settings in the Settings page

### Configuration

Create or edit `/etc/config/qmodem`:

```
config modem 'modem1'
	option enabled '1'
	option name 'Main Modem'
	option path '/sys/bus/usb/devices/1-1'
	option manufacturer 'Quectel'
	option platform 'RG500Q'
	option at_port '/dev/ttyUSB2'
	option data_interface 'wwan0'
	option proto 'qmi'
	option pdp_index '1'
	option auto_apn '1'

config global
	option enabled '1'
	option debug '0'
	option log_level 'info'
	option scan_interval '30'
	option auto_detect '1'

config dial
	option enabled '1'
	option interval '10'
	option retry '3'
	option timeout '30'
```

### API Usage

The QModem API can be accessed via ubus:

```bash
# Get modem base information
ubus call qmodem base_info '{"config_section":"modem1"}'

# Get network information
ubus call qmodem network_info '{"config_section":"modem1"}'

# Send AT command
ubus call qmodem send_at '{"config_section":"modem1","params":{"port":"/dev/ttyUSB2","at":"AT+CIMI"}}'

# Reboot modem
ubus call qmodem do_reboot '{"config_section":"modem1","params":{"method":"soft"}}'
```

## Development

### Adding New Features

1. Edit the appropriate view file in `htdocs/luci-static/resources/view/qmodem/`
2. Add new API methods in `htdocs/luci-static/resources/qmodem/qmodem.js`
3. Update translations in `po/zh_Hans/luci-app-qmodem-next.po`
4. Update ACL permissions in `root/usr/share/rpcd/acl.d/luci-app-qmodem-next.json`

### Building

```bash
cd luci-app-qmodem-next
make package/luci-app-qmodem-next/compile V=s
```

## License

GPLv3

## Author

Tom <fjrcn@outlook.com>

## Changelog

### Version 1.0.0
- Initial release with modern JavaScript UI
- Support for multiple modems
- Real-time status monitoring
- AT command interface
- Comprehensive modem information display
