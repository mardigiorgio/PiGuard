# Hardware Guide

This guide helps you choose the right Raspberry Pi and Wi-Fi adapter for running PiGuard in your home.

## Which Raspberry Pi Should You Get?

| Pi Model | Works? | How Well? | What's It Good For? |
|----------|--------|-----------|---------------------|
| **Raspberry Pi 5** | ✓ Yes | Excellent | Best choice if you want top performance |
| **Raspberry Pi 4B** | ✓ Yes | Very Good | Great all-around choice for most homes |
| **Raspberry Pi 4A** | ✓ Yes | Good | Solid option for smaller homes |
| **Raspberry Pi 3B+** | ✓ Yes | Pretty Good | Perfect for typical home Wi-Fi monitoring |
| **Raspberry Pi 3B** | ✓ Yes | Decent | Works fine, just a bit slower |
| **Raspberry Pi Zero 2 W** | ⚠ Maybe | Limited | Only basic monitoring, might struggle |
| **Raspberry Pi Zero W** | ✗ No | Too Slow | Not powerful enough for PiGuard |

## Wi-Fi Adapters: Built-in vs USB

### Built-in Wi-Fi (What comes with your Pi)

Good news! The Wi-Fi that comes built into most Raspberry Pi models works great with PiGuard:

| Pi Model | Built-in Wi-Fi | Works for PiGuard? | Performance |
|----------|---------------|-------------------|-------------|
| Pi 5 | Broadcom BCM2712 | ✓ Yes | Excellent |
| Pi 4 | Broadcom BCM43455 | ✓ Yes | Very Good |
| Pi 3B+ | Broadcom BCM43455 | ✓ Yes | Good |
| Pi 3B | Broadcom BCM43438 | ✓ Yes | Basic but fine |
| Pi Zero 2 W | Broadcom BCM43436 | ✓ Yes | Limited |

### USB Wi-Fi Adapters (Optional)

You might want an external USB Wi-Fi adapter if:
- You want better range or performance
- You want to monitor 5GHz networks (older Pi models only do 2.4GHz)
- You want to keep your built-in Wi-Fi for internet while using USB for monitoring

#### Good Options for Home Use

| Adapter | What Bands? | Works Well? | Cost | Notes |
|---------|-------------|-------------|------|-------|
| **Alfa AWUS036ACS** | 2.4GHz + 5GHz | ✓ Excellent | ~$35 | Best overall choice |
| **TP-Link AC600 T2U** | 2.4GHz + 5GHz | ✓ Good | ~$22 | Good budget option |
| **Panda PAU09** | 2.4GHz only | ✓ Good | ~$18 | Cheap and reliable |
| **Alfa AWUS036NEH** | 2.4GHz only | ✓ Good | ~$23 | Popular choice |

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

## Recommended Setups

### Best Overall (Recommended)
**Hardware**: Raspberry Pi 4B + Built-in Wi-Fi
- **Total Cost**: ~$75
- **Why**: Great performance, easy setup, built-in Wi-Fi works perfectly
- **Good for**: Most home networks

### Budget Option
**Hardware**: Raspberry Pi 3B+ + Built-in Wi-Fi
- **Total Cost**: ~$55
- **Why**: Cheaper but still works well for home monitoring
- **Good for**: Simple home setups, learning about Wi-Fi security

### High Performance
**Hardware**: Raspberry Pi 5 + Alfa USB adapter
- **Total Cost**: ~$110
- **Why**: Maximum performance and range
- **Good for**: Large homes, want to monitor 5GHz thoroughly, tech enthusiasts

### Ultra Budget
**Hardware**: Raspberry Pi 3B + Built-in Wi-Fi
- **Total Cost**: ~$35 (if you find a Pi 3B used)
- **Why**: Cheapest option that still works
- **Good for**: Just want to try PiGuard, very basic monitoring

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