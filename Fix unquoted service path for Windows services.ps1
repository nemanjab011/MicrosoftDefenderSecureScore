


## Grab all the registry keys pertinent to services
$result = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services'
$ServiceItems = $result | Foreach-Object {Get-ItemProperty $_.PsPath}

# Iterate through the keys and check for Unquoted ImagePath's
ForEach ($si in $ServiceItems) {
	if ($si.ImagePath -ne $nul) { 
		$obj = New-Object -Typename PSObject
		$obj | Add-Member -MemberType NoteProperty -Name Status -Value "Retrieved"
		# There is certianly a way to use the full path here but for now I trim it until I can find time to play with it
        	$obj | Add-Member -MemberType NoteProperty -Name Key -Value $si.PSPath.TrimStart("Microsoft.PowerShell.Core\Registry::")
        	$obj | Add-Member -MemberType NoteProperty -Name ImagePath -Value $si.ImagePath
		
		########################################################################
    		# Find and Fix Bad Keys for each key object
    		########################################################################
		
		#We're looking for keys with spaces in the path and unquoted
		$examine = $obj.ImagePath
		if (!($examine.StartsWith('"'))) { #Doesn't start with a quote
			if (!($examine.StartsWith("\??"))) { #Some MS Services start with this but don't appear vulnerable
				if ($examine.contains(" ")) { #If contains space
					#when I get here, I can either have a good path with arguments, or a bad path
					if ($examine.contains("-") -or $examine.contains("/")) { #found arguments, might still be bad
						#split out arguments
						$split = $examine -split " -", 0, "simplematch"
						$split = $split[0] -split " /", 0, "simplematch"
						$newpath = $split[0].Trim(" ") #Path minus flagged args
						if ($newpath.contains(" ")){
							#check for unflagged argument
							$eval = $newpath -Replace '".*"', '' #drop all quoted arguments
							$detunflagged = $eval -split "\", 0, "simplematch" #split on foler delim
							if ($detunflagged[-1].contains(" ")){ #last elem is executable and any unquoted args
								$fixarg = $detunflagged[-1] -split " ", 0, "simplematch" #split out args
								$quoteexe = $fixarg[0] + '"' #quote that EXE and insert it back
								$examine = $examine.Replace($fixarg[0], $quoteexe)
								$examine = $examine.Replace($examine, '"' + $examine)
								$badpath = $true
							} #end detect unflagged
							$examine = $examine.Replace($newpath, '"' + $newpath + '"')
							$badpath = $true
						} #end if newpath
						else { #if newpath doesn't have spaces, it was just the argument tripping the check
							$badpath = $false
						} #end else
					} #end if parameter
					else
					{#check for unflagged argument
						$eval = $examine -Replace '".*"', '' #drop all quoted arguments
						$detunflagged = $eval -split "\", 0, "simplematch"
						if ($detunflagged[-1].contains(" ")){
							$fixarg = $detunflagged[-1] -split " ", 0, "simplematch"
							$quoteexe = $fixarg[0] + '"'
							$examine = $examine.Replace($fixarg[0], $quoteexe)
							$examine = $examine.Replace($examine, '"' + $examine)
							$badpath = $true
						} #end detect unflagged
						else
						{#just a bad path
							#surround path in quotes
							$examine = $examine.replace($examine, '"' + $examine + '"')
							$badpath = $true
						}#end else
					}#end else
				}#end if contains space
				else { $badpath = $false }
			} #end if starts with \??
			else { $badpath = $false }
		} #end if startswith quote
		else { $badpath = $false }

		#Update Objects
		if ($badpath -eq $false){
			$obj | Add-Member -MemberType NoteProperty -Name BadKey -Value "No"
			$obj | Add-Member -MemberType NoteProperty -Name FixedKey -Value "N/A"
			$obj = $nul #clear $obj
		}
			
		# Plans to change this check. I believe it can be done more efficiently. But It works for now!
		if ($badpath -eq $true){
			$obj | Add-Member -MemberType NoteProperty -Name BadKey -Value "Yes"
			#sometimes we catch doublequotes
			if ($examine.endswith('""')){ $examine = $examine.replace('""','"') }
			$obj | Add-Member -MemberType NoteProperty -Name FixedKey -Value $examine
			if ($obj.badkey -eq "Yes"){
				#Write-Progress -Activity "Fixing $($obj.key)" -Status "Working..."
				$regpath = $obj.Fixedkey
				$obj.status = "Fixed"
	        		$regkey = $obj.key.replace('HKEY_LOCAL_MACHINE', 'HKLM:')
	        		# Comment the next line out to run without modifying the registry
				# Alternatively uncomment any line with Write-Output or Write-Object for extra verbosity.
				Set-ItemProperty -Path $regkey -name 'ImagePath' -value $regpath
			}				
		$obj = $nul #clear $obj
		}
	}
}	
