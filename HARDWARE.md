# Hardware Compatibility Guide

This guide provides comprehensive hardware requirements and compatibility information for PiGuard Wi-Fi Intrusion Detection System deployment.

## Supported Raspberry Pi Models

| Model | Support Status | Performance Level | Recommended Use Case |
|-------|---------------|-------------------|---------------------|
| **Raspberry Pi 5** | ✓ Fully Supported | Excellent | Production deployments |
| **Raspberry Pi 4B** | ✓ Fully Supported | Very Good | General purpose monitoring |
| **Raspberry Pi 4A** | ✓ Supported | Good | Small network monitoring |
| **Raspberry Pi 3B+** | ✓ Supported | Adequate | Home network protection |
| **Raspberry Pi 3B** | ✓ Supported | Basic | Limited monitoring scope |
| **Raspberry Pi Zero 2 W** | ⚠ Limited Support | Minimal | Basic threat detection only |
| **Raspberry Pi Zero W** | ✗ Not Recommended | Insufficient | Inadequate processing power |

## Wi-Fi Adapter Compatibility

### Built-in Wi-Fi Controllers

| Pi Model | Wi-Fi Controller | Monitor Mode Support | Performance Rating |
|----------|-----------------|---------------------|-------------------|
| Pi 5 | Broadcom BCM2712 | ✓ Yes | Excellent |
| Pi 4 | Broadcom BCM43455 | ✓ Yes | Very Good |
| Pi 3B+ | Broadcom BCM43455 | ✓ Yes | Good |
| Pi 3B | Broadcom BCM43438 | ✓ Yes | Basic |
| Pi Zero 2 W | Broadcom BCM43436 | ✓ Yes | Limited |

### External USB Wi-Fi Adapters

#### Highly Recommended Adapters

| Adapter Model | Chipset | Frequency Bands | Monitor Mode | Price Range |
|---------------|---------|----------------|--------------|-------------|
| **Alfa AWUS036ACS** | Realtek RTL8811AU | 2.4GHz / 5GHz | ✓ Excellent | $30-40 USD |
| **Alfa AWUS036AC** | Realtek RTL8812AU | 2.4GHz / 5GHz | ✓ Excellent | $35-45 USD |
| **Panda PAU09** | Ralink RT5372 | 2.4GHz | ✓ Good | $15-20 USD |
| **TP-Link AC600 T2U** | Realtek RTL8811AU | 2.4GHz / 5GHz | ✓ Good | $20-25 USD |

#### Alternative Options

| Adapter Model | Chipset | Frequency Bands | Monitor Mode | Price Range |
|---------------|---------|----------------|--------------|-------------|
| **Alfa AWUS036NH** | Ralink RT3070 | 2.4GHz | ✓ Good | $25-30 USD |
| **Alfa AWUS036NEH** | Ralink RT3070 | 2.4GHz | ✓ Good | $20-25 USD |
| **TP-Link N150 TL-WN722N** | Atheros AR9271 | 2.4GHz | ✓ Basic | $10-15 USD |

#### Limited Support Adapters

| Adapter Category | Chipset Examples | Known Issues | Recommended Action |
|-----------------|-----------------|--------------|-------------------|
| Realtek RTL8188* | RTL8188EU/CUS | Driver stability issues | Use with caution |
| Broadcom USB | Various | Poor Linux support | Avoid for PiGuard |
| Generic dongles | Unknown/Various | Unpredictable compatibility | Verify chipset before purchase |

### Chipset Compatibility Matrix

#### Excellent Support (Recommended)
- **Atheros AR9271** - Native Linux support, stable monitor mode
- **Ralink RT3070/RT5372** - Comprehensive monitor mode functionality
- **Realtek RTL8811AU/RTL8812AU** - Good performance with proper drivers

#### Limited Support (Use with Caution)
- **Broadcom chipsets** - Generally poor USB adapter support on Linux
- **MediaTek MT7601** - Basic functionality, limited performance
- **Realtek RTL8188EU** - Requires additional driver configuration

#### Not Recommended
- **Realtek RTL8188CUS** - Poor monitor mode implementation
- **Broadcom BCM43143** - Proprietary driver complications
- **Unknown/Generic chipsets** - Unpredictable compatibility

## Performance Benchmarks

### Packet Capture Capacity

| Hardware Configuration | Maximum Packets/Second | Suitable Environment |
|------------------------|------------------------|---------------------|
| **Pi 5 + Alfa AWUS036ACS** | ~50,000 | Enterprise monitoring |
| **Pi 4 + Built-in Wi-Fi** | ~30,000 | Office networks |
| **Pi 3B+ + RT3070 USB** | ~15,000 | Small business |
| **Pi Zero 2W + Built-in** | ~5,000 | Home networks |

### Memory Usage Profiles

| Pi Model | Total RAM | PiGuard Usage | Available for System |
|----------|-----------|---------------|---------------------|
| **Pi 5 (8GB)** | 8GB | ~200MB | 7.8GB |
| **Pi 4 (4GB)** | 4GB | ~150MB | 3.85GB |
| **Pi 3B+** | 1GB | ~120MB | 880MB |
| **Pi Zero 2W** | 512MB | ~100MB | 412MB |

## Recommended System Configurations

### Enterprise Deployment
**Hardware**: Raspberry Pi 5 + Alfa AWUS036ACS
- **Total Cost**: ~$110 USD
- **Performance**: Professional-grade monitoring capability
- **Configuration**: External adapter for monitoring, built-in Wi-Fi for management connectivity

### Standard Office Setup
**Hardware**: Raspberry Pi 4B + Built-in Wi-Fi controller
- **Total Cost**: ~$75 USD
- **Performance**: Excellent for most business environments
- **Configuration**: Built-in Wi-Fi for monitoring, Ethernet for management

### Budget Home Protection
**Hardware**: Raspberry Pi 3B+ + TP-Link TL-WN722N
- **Total Cost**: ~$50 USD
- **Performance**: Basic but functional monitoring
- **Configuration**: USB adapter for monitoring, Ethernet recommended for stability

### Multi-Point Coverage
**Hardware**: Multiple Pi 5 units with Alfa adapters
- **Cost per Unit**: ~$110 USD
- **Performance**: Comprehensive network coverage
- **Configuration**: Distributed monitoring points with centralized management

## Storage Requirements

### SD Card Specifications

| Use Case | Minimum Capacity | Recommended Capacity | Performance Class |
|----------|-----------------|---------------------|------------------|
| **Basic Deployment** | 16GB | 32GB | Class 10, A1 |
| **Production Use** | 32GB | 64GB | Class 10, A2 |
| **Extended Logging** | 64GB | 128GB | Class 10, A2 |

### Database Growth Estimates

| Network Activity Level | Daily Growth | Monthly Growth | Annual Growth |
|----------------------|--------------|----------------|---------------|
| **Quiet home network** | ~5MB | ~150MB | ~1.8GB |
| **Active office network** | ~50MB | ~1.5GB | ~18GB |
| **High-traffic environment** | ~200MB | ~6GB | ~72GB |

## Power and Environmental Requirements

### Power Consumption

| Configuration | Idle Power | Active Monitoring | Peak Usage |
|---------------|------------|------------------|------------|
| **Pi 5 + USB Wi-Fi** | 3W | 5W | 8W |
| **Pi 4 + Built-in Wi-Fi** | 2W | 4W | 6W |
| **Pi 3B+ + USB Wi-Fi** | 1.5W | 3W | 4W |

### Power Supply Requirements

| Pi Model | Official PSU | Alternative Options |
|----------|-------------|-------------------|
| **Pi 5** | 27W USB-C | Quality 30W+ USB-C adapter |
| **Pi 4** | 15W USB-C | Quality 18W+ USB-C adapter |
| **Pi 3B+** | 12W Micro-USB | Quality 2.5A Micro-USB supply |

### Operating Environment

- **Temperature Range**: 0°C to 85°C (32°F to 185°F)
- **Recommended Range**: 10°C to 60°C (50°F to 140°F)
- **Humidity**: 5% to 95% non-condensing
- **Cooling**: Passive heatsinks recommended, active cooling for continuous high-load operation

### Enclosure Considerations
- **Basic Protection**: Official Raspberry Pi cases with ventilation
- **Active Cooling**: Cases with integrated cooling fans
- **Industrial Use**: IP65-rated enclosures for harsh environments
- **Outdoor Deployment**: Weather-resistant enclosures with proper sealing

## Hardware Validation

### Pre-Purchase Verification

Before acquiring hardware, verify compatibility:

```bash
# Check existing Wi-Fi interfaces
iw dev

# Test monitor mode capability
sudo iw dev wlan0 interface add mon0 type monitor
sudo ip link set mon0 up
sudo iw dev mon0 del

# Verify packet capture functionality
sudo tcpdump -i wlan0 -c 10
```

### Post-Installation Testing

The PiGuard installer includes integrated hardware validation:
- Wi-Fi interface monitor mode verification
- Packet capture rate assessment
- Memory and storage capacity checks
- Network connectivity validation

## Hardware Selection Guidelines

### Performance Priority
For maximum detection capability:
1. **Raspberry Pi 5** for processing power
2. **Dual-band USB adapter** for comprehensive coverage
3. **High-speed SD card** for data throughput
4. **Quality power supply** for system stability

### Budget Optimization
For cost-effective deployment:
1. **Raspberry Pi 4B** for balanced performance
2. **Built-in Wi-Fi** to minimize additional hardware
3. **Standard Class 10 SD card** for adequate performance
4. **Official power supply** for reliability

### Specific Requirements
- **2.4GHz only**: Raspberry Pi 3B+ with built-in Wi-Fi sufficient
- **5GHz monitoring**: External dual-band adapter required
- **Enterprise deployment**: Pi 5 with professional-grade USB adapter
- **Multiple locations**: Standardize on Pi 4B for consistency

## Troubleshooting Hardware Issues

### Interface Detection Problems
```bash
# Check USB device recognition
lsusb

# Verify driver loading
dmesg | grep -i wireless

# Install additional firmware
sudo apt install firmware-realtek firmware-atheros
```

### Monitor Mode Failures
- Verify chipset compatibility using tables above
- Check driver version and kernel module loading
- Consider alternative USB Wi-Fi adapter
- Review system logs for error messages

### Performance Issues
- Monitor CPU usage during operation: `htop`
- Check memory availability: `free -h`
- Verify SD card performance: `hdparm -Tt /dev/mmcblk0`
- Review network interface statistics: `cat /proc/net/dev`

## Support and Compatibility Questions

For hardware-specific questions:
- **Compatibility verification**: [GitHub Discussions](https://github.com/mardigiorgio/PiGuard/discussions) with `hardware` tag
- **Performance issues**: [GitHub Issues](https://github.com/mardigiorgio/PiGuard/issues) with detailed system specifications
- **Purchasing guidance**: Community recommendations in project discussions

When reporting hardware issues, include:
- Raspberry Pi model and revision
- Wi-Fi adapter make, model, and chipset
- Operating system version and kernel information
- Output of `lsusb`, `iw dev`, and `dmesg` commands