function Send-WakeOnLan {
    <#
    .SYNOPSIS
        Sends a Wake-on-LAN magic packet to a specified MAC address.
    .PARAMETER MacAddress
        The MAC address of the target computer.
    .PARAMETER Port
        The UDP port to send the magic packet to (default: 40000).
    .PARAMETER FilePath
        The path to the file containing the MAC address. If not specified, the script will look for a file named '.env' in the current directory.
    .EXAMPLE
        Send-WakeOnLan
    .EXAMPLE
        Send-WakeOnLan -MacAddress "11-22-33-44-55-66"
    .EXAMPLE
        Send-WakeOnLan -FilePath "C:\path\to\.env"
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [ValidatePattern('^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$')]
        [string]$MacAddress,

        [Parameter()]
        [int]$Port = 40000,

        [Parameter()]
        [ValidateScript({ Test-Path $_ })]
        [string]$FilePath = '.\.env'
    )

    process {
        try {
            if (-not $MacAddress) {
                $MacAddress = Get-Content $FilePath |
                Where-Object { $_ -match '^MAC_ADDRESS:' } |
                ForEach-Object { $_ -replace 'MAC_ADDRESS:', '' }

                if (-not $MacAddress) {
                    throw "MAC_ADDRESS not found in file: $FilePath"
                }

                if (-not ($MacAddress -match '^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$')) {
                    throw "Invalid MAC address format in file: $FilePath"
                }
            }

            # Convert MAC address to byte array
            $MacByteArray = $MacAddress -split '[:-]' | ForEach-Object { [Byte] "0x$_" }

            # Create magic packet (6 bytes of 0xFF followed by 16 repetitions of MAC address)
            [Byte[]]$MagicPacket = (, [Byte]255 * 6)
            for ($i = 0; $i -lt 16; $i++) {
                $MagicPacket += $MacByteArray
            }

            $UdpClient = New-Object System.Net.Sockets.UdpClient
            try {
                # Create endpoint for broadcast
                $IPEndPoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, $Port)

                # Configure socket
                $UdpClient.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::Broadcast, $true)

                # Send packet
                [void]$UdpClient.Send($MagicPacket, $MagicPacket.Length, $IPEndPoint)
                Write-Verbose "Magic packet sent successfully to $MacAddress"
            }
            finally {
                $UdpClient.Close()
                $UdpClient.Dispose()
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

# Main script execution
try {
    Send-WakeOnLan -FilePath '.\.env' -Verbose
}
catch {
    Write-Error "Error: $_"
    exit 1
}