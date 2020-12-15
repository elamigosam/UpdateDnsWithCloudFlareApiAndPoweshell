$key = "xxxxxx"
$email = "owner@email.com"
$zone = "example.com"
$record = "subdomain"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	if ($record) {
		$hostname = "$record.$zone"
	} else {
		$hostname = "$zone"
    }

        $headers = @{
            'X-Auth-Key' = $key
            'X-Auth-Email' = $email
	    }
    
	Write-Output "Resolving external IP"
	try { 
    $ipaddr = Invoke-RestMethod http://ipinfo.io/json | Select-Object -ExpandProperty ip 
    }
	catch { 
    throw "Can't get external IP Address. Quitting." 
    }

	if ($ipaddr -eq $null) { throw "Can't get external IP Address. Quitting." }
	Write-Output "External IP is $ipaddr"
	
	Write-Output "Getting Zone information from CloudFlare"
	$baseurl = "https://api.cloudflare.com/client/v4/zones"
	$zoneurl = "$($baseurl)?name=$zone"

	try { 
$cfzone = Invoke-RestMethod -Uri $zoneurl -Method Get -Headers $headers 
} 
	catch { throw $_.Exception }

	if ($cfzone.result.count -gt 0) { $zoneid = $cfzone.result.id } else { throw "Zone $zone does not exist" }
	
	Write-Output "Getting current IP for $hostname"
	$recordurl = "$baseurl/$zoneid/dns_records/?name=$hostname"
	
	if ($usedns -eq $true) { 
		try { 
			$cfipaddr = [System.Net.Dns]::GetHostEntry($hostname).AddressList[0].IPAddressToString
			Write-Output "$hostname resolves to $cfipaddr"
		} catch {
			$new = $true
			Write-Output "Hostname does not currently exist or cannot be resolved"
		}
	} else {
		try { $dnsrecord = Invoke-RestMethod -Headers $headers -Method Get -Uri $recordurl } 
		catch { throw $_.Exception }
		
		if ($dnsrecord.result.count -gt 0) {
			$cfipaddr = $dnsrecord.result.content
			Write-Output "$hostname resolves to $cfipaddr"
		} else {
			$new = $true
			Write-Output "Hostname does not currently exist"
		}
	}
	
	# If nothing has changed, quit
	if ($cfipaddr -eq $ipaddr) {
		Write-Output "No updates required"
		return
	} elseif ($new -ne $true) {
		Write-Output "IP has changed, initiating update"
	}
	
	# If the ip has changed or didn't exist, update or add
	if ($usedns) {
		Write-Output "Getting CloudFlare Info"
		try { $dnsrecord = Invoke-RestMethod -Headers $headers -Method Get -Uri $recordurl } 
		catch { throw $_.Exception }
	}
	
	# if the record exists, then udpate it. Otherwise, add a new record.
	if ($dnsrecord.result.count -gt 0) {
		Write-Output "Updating CloudFlare record for $hostname"
		$recordid = $dnsrecord.result.id
		$dnsrecord.result | Add-Member "content"  $ipaddr -Force 
		$body = $dnsrecord.result | ConvertTo-Json
		
		$updateurl = "$baseurl/$zoneid/dns_records/$recordid" 
		$result = Invoke-RestMethod -Headers $headers -Method Put -Uri $updateurl -Body $body -ContentType "application/json"
		$newip = $result.result.content
		Write-Output "Updated IP to $newip"
	} else {
		Write-Output "Adding $hostname to CloudFlare"
		$newrecord = @{
			"type" = "A"
			"name" =  $hostname
			"content" = $ipaddr
		}
		
		$body = ConvertTo-Json -InputObject $newrecord
		$newrecordurl = "$baseurl/$zoneid/dns_records"
		
		try {
			$request = Invoke-RestMethod -Uri $newrecordurl -Method Post -Headers $headers -Body $body -ContentType "application/json"
			Write-Output "Done! $hostname will now resolve to $ipaddr."
		} catch {
			Write-Warning "Couldn't update :("
			throw $_.Exception
		}
	}
