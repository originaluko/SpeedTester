#Requires -Version 3
function Start-SpeedTest
{
    <#
            .SYNOPSIS
            Report your internet Download and Upload speed.
 
            .DESCRIPTION
            SpeedTester leverages speedtest.net hosting servers.  SpeedTester will identify the closest hosting servers
            to you and pick the one with the lowest latency to perform a test download and upload.  It will then report 
            the average Download and Upload in Mbps.
            
            Start-SpeedTest does not accept any parameters at this stage.

            .EXAMPLE
            Start-SpeedTest

            .INPUTS
            None
 
            .NOTES
            Author:  Mark Ukotic
            Website: http://blog.ukotic.net
            Twitter: @originaluko
            GitHub:  https://github.com/originaluko/

            .LINKS

    #>

    [CmdletBinding()]
    Param(
    )

    # Server distance helper function 
    function Get-ServerInfo {
    
        param(
            [Parameter(Mandatory=$true)]
            $servers 
         )
          
        foreach($server in $servers) 
        { 
            $radius = 6371
            [float]$dlat = ([float]$orilat - [float]$server.lat) * 3.14 / 180
            [float]$dlon = ([float]$orilon - [float]$server.lon) * 3.14 / 180
            [float]$a = [math]::Sin([float]$dlat/2) * [math]::Sin([float]$dlat/2) + [math]::Cos([float]$orilat * 3.14 / 180 ) * [math]::Cos([float]$server.lat * 3.14 / 180 ) * [math]::Sin([float]$dlon/2) * [math]::Sin([float]$dlon/2)
            [float]$c = 2 * [math]::Atan2([math]::Sqrt([float]$a ), [math]::Sqrt(1 - [float]$a))
            [float]$d = [float]$radius * [float]$c

            New-Object PSObject -Property @{
                Distance = $d
                Country = $server.country
                Sponsor = $server.sponsor
                Url = $server.url
                Host = $server.host
            }
        }
    }

    # Avg Ping response helper function
    function Get-AvgPing {  
        param(
            [Parameter(Mandatory=$true)]
            $servers 
        )

        foreach ($server in $servers) { 
     
            $test = (Test-Connection -ComputerName $server -Count 4  | measure-Object -Property ResponseTime -Average).average 
            $response = ($test -as [decimal] ) 
    
            New-Object PSObject -Property @{
                'Destination' = $server
                'Avg' = $response
            }
        } 
    }
    
    # Download Test helper function
    function Get-DataWCAsync{
        param(
            [Parameter(Mandatory=$true)]
            $Url, 
            [switch]$IncludeStats
        )
        $wc = New-Object Net.WebClient
        $wc.UseDefaultCredentials = $false
        $wc.Headers.Add("Content-Type","application/x-www-form-urlencoded") 
        $wc.Headers.Add("Accept: text/html, application/xhtml+xml, */*")
        $wc.Headers.Add("User-Agent", "Mozilla/4.0 (compatible; MSIE 6.0;Windows NT 5.1; .NET CLR 1.0.3705; .NET CLR 1.1.4322)")
        $wc.Headers.Add("Cache-Control", "no-cache")
        $wc.Headers.Add("Referer", "http://www.speedtest.net")
        $start = Get-Date 
        $null = Register-ObjectEvent -InputObject $wc -EventName DownloadProgressChanged -MessageData @{start=$start;includeStats=$includestats} -SourceIdentifier WebClient.DownloadProgressChanged -Action { 
            filter Get-FileSize {
                "{0:N2} {1}" -f $(
                    if ($_ -lt 1kb) { $_, 'Bytes' }
                    elseif ($_ -lt 1mb) { ($_/1kb), 'KB' }
                    elseif ($_ -lt 1gb) { ($_/1mb), 'MB' }
                    elseif ($_ -lt 1tb) { ($_/1gb), 'GB' }
                    elseif ($_ -lt 1pb) { ($_/1tb), 'TB' }
                    else { ($_/1pb), 'PB' }
                )
            }
            $time = ((Get-Date) - $event.MessageData.start)
            $averagespeed = ($eventargs.BytesReceived * 8 / 1MB) / $time.TotalSeconds
            $elapsed = $Time.ToString('hh\:mm\:ss')
            $remainingseconds = ($eventargs.TotalBytesToReceive - $eventargs.BytesReceived) * 8 / 1MB / $averagespeed
            $receivedsize = $eventargs.BytesReceived | Get-FileSize
            $totalSize = $eventargs.TotalBytesToReceive | Get-FileSize  
                          
            Write-Progress -Activity (" $url {0:N2} Mbps" -f $averagespeed) -Status ("{0} of {1} ({2}% in {3})" -f $receivedSize,$totalsize,$eventargs.ProgressPercentage,$elapsed) -SecondsRemaining $remainingseconds -PercentComplete $eventargs.ProgressPercentage
            if ($eventargs.ProgressPercentage -eq 100){
                Write-Progress -Activity (" $url {0:N2} Mbps" -f $averagespeed) -Status 'Done' -Completed
                
                if ($event.MessageData.includeStats.IsPresent){
                    $global:down = [Math]::Round($averageSpeed, 2) 
                 } 
            }
        }    
        $null = Register-ObjectEvent -InputObject $wc -EventName DownloadDataCompleted -SourceIdentifier WebClient.DownloadDataCompleted -Action { 
            Unregister-Event -SourceIdentifier WebClient.DownloadProgressChanged
            Unregister-Event -SourceIdentifier WebClient.DownloadDataCompleted
        }
    
        try  {  
            $wc.DownloadDataAsync($url)  
        }  
        catch [System.Net.WebException]  {  
            Write-Warning "Download of $url failed"  
        }   
        finally  {    
            while ($wc.IsBusy) {}
            $wc.Dispose() 
        }  
    }
    
    # Upload Test helper function
    function Push-DataWCAsync{
        param(
            [Parameter(Mandatory=$true)]
            $url, 
            $byteArray,
            [switch]$includeStats
        )
        $wc = New-Object Net.WebClient
        $wc.UseDefaultCredentials = $false
        $wc.Headers.Add("Content-Type","application/x-www-form-urlencoded") 
        $wc.Headers.Add("Accept: text/html, application/xhtml+xml, */*")
        $wc.Headers.Add("User-Agent", "Mozilla/4.0 (compatible; MSIE 6.0;Windows NT 5.1; .NET CLR 1.0.3705; .NET CLR 1.1.4322)")
        $wc.Headers.Add("Cache-Control", "no-cache")
        $wc.Headers.Add("Referer", "http://www.speedtest.net")
        $start = Get-Date 
        $null = Register-ObjectEvent -InputObject $wc -EventName UploadProgressChanged -MessageData @{start=$start;includeStats=$includeStats} -SourceIdentifier WebClient.UploadProgressChanged -Action { 
            filter Get-FileSize {
                "{0:N2} {1}" -f $(
                    if ($_ -lt 1kb) { $_, 'Bytes' }
                    elseif ($_ -lt 1mb) { ($_/1kb), 'KB' }
                    elseif ($_ -lt 1gb) { ($_/1mb), 'MB' }
                    elseif ($_ -lt 1tb) { ($_/1gb), 'GB' }
                    elseif ($_ -lt 1pb) { ($_/1tb), 'TB' }
                    else { ($_/1pb), 'PB' }
                )
            }
            
            $Time = ((Get-Date) - $event.MessageData.start)
            $averageSpeed = ($eventargs.BytesSent * 8 / 1MB) / $Time.TotalSeconds
            $elapsed = $Time.ToString('hh\:mm\:ss')
            $remainingSeconds = ($eventargs.TotalBytesToSend - $eventargs.BytesSent) * 8 / 1MB / $averageSpeed
            $receivedSize = $eventargs.BytesSent | Get-FileSize
            $totalSize = $eventargs.TotalBytesToSend | Get-FileSize  
            $percent = $eventargs.BytesSent / $eventargs.TotalBytesToSend * 100
            $percent = [Math]::Round($percent)   
                       
            Write-Progress -Activity (" $url {0:N2} Mbps" -f $averageSpeed) -Status ("{0} of {1} ({2}% in {3})" -f $receivedSize,$totalSize,$percent,$elapsed) -SecondsRemaining $remainingSeconds -PercentComplete $percent
            if ($eventargs.ProgressPercentage -eq 100){
                Write-Progress -Activity (" $url {0:N2} Mbps" -f $averageSpeed) -Status 'Done' -Completed
                
                if ($event.MessageData.includeStats.IsPresent){
                    $global:upload = [Math]::Round($averageSpeed, 2) 
                }
            }
        }    
        # $null = Register-ObjectEvent -InputObject $wc -EventName UploadDataCompleted -SourceIdentifier WebClient.UploadDataCompleted -Action { 
        #    Unregister-Event -SourceIdentifier WebClient.UploadProgressChanged -Force
        #    Unregister-Event -SourceIdentifier WebClient.UploadDataCompleted -Force
        # }  
        
        try  {  
            $wc.UploadDataAsync($url,'POST',$byteArray) 
        }  
        catch [System.Net.WebException]  {  
            Write-Warning "Upload of $url failed"  
        }   
        finally  { 
            while ($wc.IsBusy) {}   
            $wc.Dispose()  
            Remove-Job * -Force
        }
    }
    
    Write-Output 'Retrieving configuration...'

    $uri = 'http://beta.speedtest.net/speedtest-config.php'
    [xml]$config = Invoke-WebRequest -Uri $uri -UseBasicParsing

    $ip = $config.settings.client.ip
    $isp = $config.settings.client.isp
    Write-Output "Testing from $isp ($ip)"

    $orilat = $config.settings.client.lat
    $orilon = $config.settings.client.lon

    Write-Output 'Retrieving server list...'

    $uri = 'http://www.speedtest.net/speedtest-servers.php'
    [xml]$hosts = Invoke-WebRequest -Uri $uri -UseBasicParsing

    Write-Output 'Selecting best server...'

    $servers = $hosts.settings.servers.server
        
    # Sort the distance of each server
    $closestserver = Get-ServerInfo -Servers $servers | Sort-Object -Property distance
    
    $servers = $closestserver[0],$closestserver[1],$closestserver[2]
    $serverurlspilt = ($servers).host -split ':8080'
    $servers = $serverurlspilt[0],$serverurlspilt[2],$serverurlspilt[4] 
    
    # Get avg ping response
    $bestserver = Get-AvgPing -servers $servers

    # Getting lazy and just want lowest latency server asap
    $index = 0
    $minvalue = [decimal]::MaxValue
    $bestserver.avg | ForEach-Object { if ($minvalue -gt $_) {$minvalue = $_; $minindex = $index}; $index++ }
     
    $location = $closestserver[$index].sponsor
    $distance = $closestserver[$index].distance
    Write-Output "Hosted by $location [$distance km] ($minvalue ms)"

    $serverurlspilt = ($closestserver[$index]).url -split 'upload'
    $url = $serverurlspilt[0] + 'random2000x2000.jpg'
    Write-Output 'Testing download speed...'
    Get-DataWCAsync -Url $url -IncludeStats 
      
    Write-Output "Download: $down Mbps"
 
    # Creating a random byte array to avoid bad download data messing with the upload
    $bytearray = New-Object Byte[] 7864320
    (New-Object Random).NextBytes($bytearray)
    
    $url = ($closestserver[$index]).url
    Write-Output 'Testing upload speed...'
    Push-DataWCAsync -url $url -byteArray $bytearray -includeStats        

    Write-Output "Upload: $upload Mbps"
    Write-Output 'Tests Completed' 
}