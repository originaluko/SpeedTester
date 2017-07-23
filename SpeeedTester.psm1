#Requires -Version 3
function Get-Speed
{
    <#
            .SYNOPSIS
            Report your internet Download and Upload speed.
 
            .DESCRIPTION
            Get-Speed leverages speedtest.net hosting servers.  Get-Speed will identify the closest hosting server
            to you and perform a test download and upload.  It will then report the average Download and Upload in Mbps.
            Get-Speed does not accept any parameters at this stage.

            .EXAMPLE
            Get-Speed

            .INPUTS
            None
 
            .NOTES
            Author:  Mark Ukotic
            Website: http://blog.ukotic.net
            Twitter: @originaluko
            GitHub: 

            .LINKS

    #>

    [CmdletBinding()]
    Param(
    )

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

    Write-Output 'Selecting closest server...'

    $servers = $hosts.settings.servers.server

    # Work out the distance of each server
    $serverinformation = foreach($server in $servers) 
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
        }
    }

    # Sort the distance of each server
    $closestserver = $serverinformation | Sort-Object -Property distance

    $location = $closestserver[0].sponsor
    $distance = $closestserver[0].distance
    Write-Output "Hosted by $location [$distance km]"


    # Perform the Download Test
    function Get-FileWCAsync{
        param(
            [Parameter(Mandatory=$true)]
            $Url, 
            [switch]$IncludeStats
        )
        $wc = New-Object Net.WebClient
        $wc.UseDefaultCredentials = $true
        $start = Get-Date 
        $global:downchange = Register-ObjectEvent -InputObject $wc -EventName DownloadProgressChanged -MessageData @{start=$start;includeStats=$includestats} -SourceIdentifier WebClient.DownloadProgressChanged -Action { 
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
            $global:output = $event.sourceeventargs.result 
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
            $wc.Dispose()  
        }  
    }

     
    $serverurlspilt = ($closestserver[0]).url -split 'upload'
    $url = $serverurlspilt[0] + 'random2000x2000.jpg'
    Write-Output 'Testing download speed...'
    Get-FileWCAsync -Url $url -IncludeStats 

 
    # Perform the Upload Test
    function Put-FileWCAsync{
        param(
            [Parameter(Mandatory=$true)]
            $url, 
            $byteArray,
            [switch]$includeStats
        )
        $wc = New-Object Net.WebClient
        $wc.UseDefaultCredentials = $true
        $wc.Headers.Add("Content-Type","application/x-www-form-urlencoded") 
        $start = Get-Date 
        $global:upchange = Register-ObjectEvent -InputObject $wc -EventName UploadProgressChanged -MessageData @{start=$start;includeStats=$includeStats} -SourceIdentifier WebClient.UploadProgressChanged -Action { 
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
                          
            Write-Progress -Activity (" $url {0:N2} Mbps" -f $averageSpeed) -Status ("{0} of {1} ({2}% in {3})" -f $receivedSize,$totalSize,$eventargs.ProgressPercentage,$elapsed) -SecondsRemaining $remainingSeconds -PercentComplete $eventargs.ProgressPercentage
            if ($eventargs.ProgressPercentage -eq 100){
                Write-Progress -Activity (" $url {0:N2} Mbps" -f $averageSpeed) -Status 'Done' -Completed
                
                if ($event.MessageData.includeStats.IsPresent){
                    $global:upload = [Math]::Round($averageSpeed, 2)
                 } 
            }
        }    
        $null = Register-ObjectEvent -InputObject $wc -EventName UploadDataCompleted -SourceIdentifier WebClient.UploadDataCompleted -Action { 
            Unregister-Event -SourceIdentifier WebClient.UploadProgressChanged
            Unregister-Event -SourceIdentifier WebClient.UploadDataCompleted
        }  
        try  {  
            $wc.UploadDataAsync($url,'POST',$byteArray) 
        
        }  
        catch [System.Net.WebException]  {  
            Write-Warning "Upload of $url failed"  
        }   
        finally  {    
            $wc.Dispose()  
        }  
    }
    
   
    # Wait until the state of DownloadProgressChange is Stopped
    Do {
    }
    Until ($global:downchange.State -eq 'Stopped'){
    } 
  
    Write-Output "Download: $global:down Mbps"
 
    [byte[]]$bytearray = $global:output
    $url = ($closestserver[0]).url
    Write-Output 'Testing upload speed...'
    Put-FileWCAsync -url $url -byteArray $bytearray -includeStats        

    # Wait until the state of UploadProgressChange is Stopped
    Do {
    }
    Until ($global:upchange.State -eq 'Stopped'){
    } 
  
    Write-Output "Upload: $global:upload Mbps"
    Write-Output 'Tests Completed' 

}