import Foundation
import IOKit

/// NVMe SMART / Health 日志（NVMe 规范 Log Page 02h），smartctl -a disk0 里的那组数据。
struct NVMeHealth: Sendable {
    var criticalWarning: UInt8
    var temperatureCelsius: Int
    var availableSpare: Int
    var availableSpareThreshold: Int
    var percentageUsed: Int
    var dataUnitsRead: Double      // 1 单位 = 512,000 字节
    var dataUnitsWritten: Double
    var powerCycles: UInt64
    var powerOnHours: UInt64
    var unsafeShutdowns: UInt64
    var mediaErrors: UInt64
    var errorLogEntries: UInt64

    var bytesRead: Double { dataUnitsRead * 512_000 }
    var bytesWritten: Double { dataUnitsWritten * 512_000 }
}

/// 通过系统自带的 NVMeSMARTLib 插件读取 SMART 数据：无需 root、无需安装 smartmontools。
/// Apple Silicon 内建 SSD 与 Intel（T2）机型均已暴露 `NVMe SMART Capable` 服务。
enum NVMeSMARTReader {

    /// 读取第一块支持 SMART 的 NVMe 设备（通常是内建 disk0）。读不到返回 nil。
    static func readInternal() -> NVMeHealth? {
        let userClientTypeID = CFUUIDGetConstantUUIDWithBytes(nil,
            0xAA, 0x0F, 0xA6, 0xF9, 0xC2, 0xD6, 0x45, 0x7F, 0xB1, 0x0B, 0x59, 0xA1, 0x32, 0x53, 0x29, 0x2F)
        let interfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
            0xCC, 0xD1, 0xDB, 0x19, 0xFD, 0x9A, 0x4D, 0xAF, 0xBF, 0x95, 0x12, 0x45, 0x4B, 0x23, 0x0A, 0xB6)
        // kIOCFPlugInInterfaceID（C 宏，Swift 不可见）
        let plugInInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
            0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)

        let matching = [kIOPropertyMatchKey: [kIOPropertyNVMeSMARTCapableKey: true]] as NSDictionary
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching as CFDictionary, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var plugin: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
            var score: Int32 = 0
            guard IOCreatePlugInInterfaceForService(service, userClientTypeID, plugInInterfaceID, &plugin, &score) == KERN_SUCCESS,
                  let plugin, let pluginVTable = plugin.pointee
            else { continue }
            defer { IODestroyPlugInInterface(plugin) }

            var raw: LPVOID?
            guard pluginVTable.pointee.QueryInterface(plugin, CFUUIDGetUUIDBytes(interfaceID), &raw) == S_OK,
                  let raw
            else { continue }
            let smart = raw.assumingMemoryBound(to: UnsafeMutablePointer<IONVMeSMARTInterface>.self)
            defer { _ = smart.pointee.pointee.Release(smart) }

            var data = NVMeSMARTData()
            guard smart.pointee.pointee.SMARTReadData(smart, &data) == kIOReturnSuccess else { continue }
            return NVMeHealth(
                criticalWarning: data.CRITICAL_WARNING,
                temperatureCelsius: Int(data.TEMPERATURE) - 273,
                availableSpare: Int(data.AVAILABLE_SPARE),
                availableSpareThreshold: Int(data.AVAILABLE_SPARE_THRESHOLD),
                percentageUsed: Int(data.PERCENTAGE_USED),
                dataUnitsRead: u128(data.DATA_UNITS_READ),
                dataUnitsWritten: u128(data.DATA_UNITS_WRITTEN),
                powerCycles: data.POWER_CYCLES.0,
                powerOnHours: data.POWER_ON_HOURS.0,
                unsafeShutdowns: data.UNSAFE_SHUTDOWNS.0,
                mediaErrors: data.MEDIA_ERRORS.0,
                errorLogEntries: data.NUM_ERROR_INFO_LOG_ENTRIES.0
            )
        }
        return nil
    }

    /// NVMe 计数器是 128 位小端（低 64 位在前）。
    private static func u128(_ v: (UInt64, UInt64)) -> Double {
        Double(v.0) + Double(v.1) * 18_446_744_073_709_551_616.0
    }
}
