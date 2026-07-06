# ============================================================================
#  TravelBridge  ·  Windows companion app
#  ---------------------------------------------------------------------------
#  A small control panel for the travel-bridge Raspberry Pi: see status, scan
#  for WiFi around you, and connect the Pi to a network — all over SSH, from
#  your laptop, with no typing of Linux commands.
#
#  Nothing here needs the internet: it talks to the Pi locally over the
#  "TravelBridge" WiFi. First launch asks for the Pi's address / login and
#  stores the password encrypted for THIS Windows user only (DPAPI).
#
#  Requires: Windows 10/11 (built-in OpenSSH client). No install, no admin.
# ============================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# ---------- paths ----------
$AppDir   = Join-Path $env:APPDATA 'TravelBridge'
$CfgFile  = Join-Path $AppDir 'settings.json'
$AskExe   = Join-Path $AppDir 'tb-askpass.exe'
$KeyFile  = Join-Path $AppDir 'tb_ed25519'
$KH       = Join-Path $AppDir 'known_hosts'
$Report   = Join-Path ([Environment]::GetFolderPath('Desktop')) 'TravelBridge-Report.txt'
if(-not (Test-Path $AppDir)){ New-Item -ItemType Directory -Path $AppDir -Force | Out-Null }

# ---------- colors ----------
function C($r,$g,$b){ [System.Drawing.Color]::FromArgb($r,$g,$b) }
$clBg=C 244 246 250; $clCard=C 255 255 255; $clLine=C 225 230 238
$clBlue=C 21 101 192; $clBlue2=C 30 136 229; $clInk=C 27 35 48; $clMut=C 96 109 130
$clGreen=C 46 125 50; $clRed=C 198 40 40; $clAmber=C 239 108 0; $clGrey=C 154 164 178

# ---------- settings (DPAPI-encrypted password) ----------
$script:Cfg = $null
function Load-Cfg {
  if(Test-Path $CfgFile){ try { $script:Cfg = Get-Content $CfgFile -Raw | ConvertFrom-Json } catch { $script:Cfg=$null } }
  if(-not $script:Cfg){ $script:Cfg = [pscustomobject]@{ User='pi'; Hosts=@('192.168.50.1','raspberrypi.local'); Enc=''; Paired=$false } }
}
function Save-Cfg { $script:Cfg | ConvertTo-Json | Out-File -FilePath $CfgFile -Encoding utf8 }
function Get-Pw {
  if(-not $script:Cfg.Enc){ return '' }
  try { $s=ConvertTo-SecureString $script:Cfg.Enc; return ([Net.NetworkCredential]::new('',$s)).Password } catch { return '' }
}
function Set-Pw([string]$plain){
  if($plain){ $script:Cfg.Enc = ConvertFrom-SecureString (ConvertTo-SecureString $plain -AsPlainText -Force) } else { $script:Cfg.Enc='' }
}

# ---------- tiny askpass helper (compiled once; reads password from env) ----------
function Ensure-Ask {
  if(Test-Path $AskExe){ return $true }
  $src = 'public class TBAsk{ public static void Main(){ System.Console.Write(System.Environment.GetEnvironmentVariable("TB_PW")); } }'
  try { Add-Type -TypeDefinition $src -OutputType ConsoleApplication -OutputAssembly $AskExe -ErrorAction Stop; return (Test-Path $AskExe) }
  catch { return $false }
}

# ---------- ssh ----------
$script:Pi = $null
function Find-Pi {
  foreach($h in $script:Cfg.Hosts){ if($h -and (Test-Connection -ComputerName $h -Count 1 -Quiet -ErrorAction SilentlyContinue)){ return $h } }
  return $null
}
function Ssh-Args {
  $a = @('-o',"UserKnownHostsFile=$KH",'-o','StrictHostKeyChecking=accept-new','-o','ConnectTimeout=10','-o','ServerAliveInterval=4','-o','ServerAliveCountMax=2')
  if($script:Cfg.Paired -and (Test-Path $KeyFile)){ $a += @('-o','BatchMode=yes','-i',$KeyFile) }
  return $a
}
function Invoke-Pi([string]$cmd){
  if(-not $script:Pi){ $script:Pi = Find-Pi }
  if(-not $script:Pi){ return $null }
  $b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($cmd -replace "`r`n","`n")))
  $remote = "echo $b64 | base64 -d | bash"
  $usePw = -not ($script:Cfg.Paired -and (Test-Path $KeyFile))
  if($usePw){
    if(-not (Ensure-Ask)){ return "ERR: could not build the login helper." }
    $env:SSH_ASKPASS=$AskExe; $env:SSH_ASKPASS_REQUIRE='force'; $env:DISPLAY='localhost:0'; $env:TB_PW=(Get-Pw)
  }
  try {
    for($t=0;$t -lt 3;$t++){
      $r=(& ssh @(Ssh-Args) "$($script:Cfg.User)@$($script:Pi)" $remote 2>&1) | Out-String
      if($r -and $r -notmatch 'Connection (timed out|refused|reset|closed|aborted)' -and $r -notmatch 'Could not resolve'){ return $r }
      Start-Sleep -Milliseconds 700; $script:Pi = Find-Pi; if(-not $script:Pi){ return $null }
    }
    return $r
  } finally { $env:TB_PW=$null }
}

# ---------- UI ----------
$form = New-Object Windows.Forms.Form
$form.Text='TravelBridge'; $form.Size=New-Object Drawing.Size(540,700)
$form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedSingle'; $form.MaximizeBox=$false
$form.BackColor=$clBg; $form.Font=New-Object Drawing.Font('Segoe UI',9.75)

$hdr=New-Object Windows.Forms.Panel; $hdr.Size=New-Object Drawing.Size(540,86); $hdr.Location=New-Object Drawing.Point(0,0)
$hdr.Add_Paint({ param($s,$e)
  $rect=New-Object Drawing.Rectangle(0,0,$s.Width,$s.Height)
  $br=New-Object Drawing.Drawing2D.LinearGradientBrush($rect,$clBlue,$clBlue2,[Drawing.Drawing2D.LinearGradientMode]::Horizontal)
  $e.Graphics.FillRectangle($br,$rect); $br.Dispose() })
$lblT=New-Object Windows.Forms.Label; $lblT.Text='  TravelBridge'; $lblT.ForeColor='White'
$lblT.Font=New-Object Drawing.Font('Segoe UI',19,[Drawing.FontStyle]::Bold); $lblT.AutoSize=$true; $lblT.BackColor='Transparent'; $lblT.Location=New-Object Drawing.Point(16,16)
$lblS=New-Object Windows.Forms.Label; $lblS.Text='   Public WiFi for your filtered device'; $lblS.ForeColor=(C 220 232 248)
$lblS.AutoSize=$true; $lblS.BackColor='Transparent'; $lblS.Location=New-Object Drawing.Point(18,54)
$hdr.Controls.AddRange(@($lblT,$lblS)); $form.Controls.Add($hdr)

function Round($ctrl,$rad){
  $gp=New-Object Drawing.Drawing2D.GraphicsPath; $d=$rad*2; $w=$ctrl.Width; $h=$ctrl.Height
  $gp.AddArc(0,0,$d,$d,180,90); $gp.AddArc($w-$d-1,0,$d,$d,270,90)
  $gp.AddArc($w-$d-1,$h-$d-1,$d,$d,0,90); $gp.AddArc(0,$h-$d-1,$d,$d,90,90); $gp.CloseAllFigures()
  $ctrl.Region=New-Object Drawing.Region($gp) }

$card=New-Object Windows.Forms.Panel; $card.Size=New-Object Drawing.Size(496,150); $card.Location=New-Object Drawing.Point(16,100); $card.BackColor=$clCard
Round $card 12
function Row($y,$name){
  $dot=New-Object Windows.Forms.Label; $dot.Text=[char]0x25CF; $dot.Font=New-Object Drawing.Font('Segoe UI',14); $dot.ForeColor=$clGrey
  $dot.AutoSize=$true; $dot.Location=New-Object Drawing.Point(16,$y); $dot.BackColor='Transparent'
  $nm=New-Object Windows.Forms.Label; $nm.Text=$name; $nm.ForeColor=$clMut; $nm.AutoSize=$true; $nm.Location=New-Object Drawing.Point(44,($y+4))
  $vl=New-Object Windows.Forms.Label; $vl.Text='--'; $vl.ForeColor=$clInk; $vl.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
  $vl.AutoSize=$true; $vl.Location=New-Object Drawing.Point(200,($y+3))
  $card.Controls.AddRange(@($dot,$nm,$vl)); return @{dot=$dot;val=$vl} }
$rHot=Row 16  'Hotspot'
$rUp =Row 56  'Pi joined WiFi'
$rNet=Row 96  'Internet'
$form.Controls.Add($card)

$btnCheck=New-Object Windows.Forms.Button; $btnCheck.Text='Check now'; $btnCheck.Size=New-Object Drawing.Size(496,44)
$btnCheck.Location=New-Object Drawing.Point(16,262); $btnCheck.FlatStyle='Flat'; $btnCheck.FlatAppearance.BorderSize=0
$btnCheck.BackColor=$clBlue; $btnCheck.ForeColor='White'; $btnCheck.Font=New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold)
$btnCheck.Cursor='Hand'; $btnCheck.Add_MouseEnter({ $btnCheck.BackColor=$clBlue2 }); $btnCheck.Add_MouseLeave({ $btnCheck.BackColor=$clBlue })
$form.Controls.Add($btnCheck)

$vp=New-Object Windows.Forms.Panel; $vp.Size=New-Object Drawing.Size(496,70); $vp.Location=New-Object Drawing.Point(16,316); $vp.BackColor=(C 233 240 250); Round $vp 10
$lblV=New-Object Windows.Forms.Label; $lblV.Text='Click "Check now" to test the connection.'; $lblV.ForeColor=$clInk
$lblV.Font=New-Object Drawing.Font('Segoe UI',10); $lblV.Location=New-Object Drawing.Point(14,10); $lblV.Size=New-Object Drawing.Size(468,50); $lblV.BackColor='Transparent'
$vp.Controls.Add($lblV); $form.Controls.Add($vp)

$gl=New-Object Windows.Forms.Label; $gl.Text='Connect the Pi to a WiFi'; $gl.ForeColor=$clMut; $gl.AutoSize=$true; $gl.Location=New-Object Drawing.Point(18,398)
$form.Controls.Add($gl)
$btnScan=New-Object Windows.Forms.Button; $btnScan.Text='Scan'; $btnScan.Size=New-Object Drawing.Size(80,30); $btnScan.Location=New-Object Drawing.Point(16,420)
$btnScan.FlatStyle='Flat'; $btnScan.BackColor='White'; $btnScan.FlatAppearance.BorderColor=$clLine; $btnScan.Cursor='Hand'
$cbo=New-Object Windows.Forms.ComboBox; $cbo.Size=New-Object Drawing.Size(406,30); $cbo.Location=New-Object Drawing.Point(106,420); $cbo.DropDownStyle='DropDownList'
$txtP=New-Object Windows.Forms.TextBox; $txtP.Size=New-Object Drawing.Size(320,30); $txtP.Location=New-Object Drawing.Point(16,458); $txtP.UseSystemPasswordChar=$true
$lblPh=New-Object Windows.Forms.Label; $lblPh.Text='WiFi password (leave empty if none)'; $lblPh.ForeColor=$clGrey; $lblPh.AutoSize=$true; $lblPh.Location=New-Object Drawing.Point(20,462); $lblPh.BackColor='White'
$txtP.Add_Enter({ $lblPh.Visible=$false }); $txtP.Add_Leave({ if(-not $txtP.Text){ $lblPh.Visible=$true } })
$btnConn=New-Object Windows.Forms.Button; $btnConn.Text='Connect'; $btnConn.Size=New-Object Drawing.Size(166,30); $btnConn.Location=New-Object Drawing.Point(346,458)
$btnConn.FlatStyle='Flat'; $btnConn.FlatAppearance.BorderSize=0; $btnConn.BackColor=$clGreen; $btnConn.ForeColor='White'; $btnConn.Cursor='Hand'; $btnConn.Font=New-Object Drawing.Font('Segoe UI',9.75,[Drawing.FontStyle]::Bold)
$form.Controls.AddRange(@($btnScan,$cbo,$txtP,$lblPh,$btnConn))

$log=New-Object Windows.Forms.TextBox; $log.Multiline=$true; $log.ReadOnly=$true; $log.ScrollBars='Vertical'
$log.Size=New-Object Drawing.Size(496,120); $log.Location=New-Object Drawing.Point(16,500); $log.BackColor=(C 15 23 41); $log.ForeColor=(C 210 220 235); $log.Font=New-Object Drawing.Font('Consolas',8.5); $log.BorderStyle='None'
$form.Controls.Add($log)

$lnkSet=New-Object Windows.Forms.LinkLabel; $lnkSet.Text='Settings'; $lnkSet.AutoSize=$true; $lnkSet.Location=New-Object Drawing.Point(16,634); $lnkSet.LinkColor=$clBlue
$lnkRep=New-Object Windows.Forms.LinkLabel; $lnkRep.Text='Open report'; $lnkRep.AutoSize=$true; $lnkRep.Location=New-Object Drawing.Point(96,634); $lnkRep.LinkColor=$clBlue
$lblTime=New-Object Windows.Forms.Label; $lblTime.Text=''; $lblTime.ForeColor=$clGrey; $lblTime.AutoSize=$true; $lblTime.Location=New-Object Drawing.Point(400,634)
$form.Controls.AddRange(@($lnkSet,$lnkRep,$lblTime))

# ---------- behavior ----------
function Set-Ind($row,$color,$text){ $row.dot.ForeColor=$color; $row.val.Text=$text; $row.val.ForeColor=$clInk }
function Logln($t){ $log.AppendText($t+"`r`n") }
function Busy($on,$msg){ $btnCheck.Enabled=-not $on; $btnScan.Enabled=-not $on; $btnConn.Enabled=-not $on; if($on){ $btnCheck.Text=$msg }else{ $btnCheck.Text='Check now' }; [Windows.Forms.Application]::DoEvents() }

$RemoteCheck = @'
source /etc/travel-bridge/runtime.conf 2>/dev/null || { UPLINK_IFACE=wlan0; AP_IFACE=ap0; }
cat > ~/tb-diag-loop.sh <<LOOP
#!/bin/bash
source /etc/travel-bridge/runtime.conf 2>/dev/null || UPLINK_IFACE=wlan0
LOG="\$HOME/tb-diag.log"
while true; do
  { echo "==== \$(date '+%Y-%m-%d %H:%M:%S') ===="
    echo "uplink: \$(nmcli -t -f GENERAL.STATE,GENERAL.CONNECTION device show \$UPLINK_IFACE 2>/dev/null | tr '\n' ' ')"
    echo "hotspot: \$(systemctl is-active hostapd 2>/dev/null)"
    echo "internet: \$(curl -4 -s -o /dev/null -w '%{http_code}' --max-time 6 http://connectivitycheck.gstatic.com/generate_204 2>/dev/null)"
  } >> "\$LOG" 2>&1
  tail -n 800 "\$LOG" > "\$LOG.tmp" 2>/dev/null && mv "\$LOG.tmp" "\$LOG"; sleep 30
done
LOOP
chmod +x ~/tb-diag-loop.sh
( crontab -l 2>/dev/null | grep -v tb-diag-loop ; echo "@reboot \$HOME/tb-diag-loop.sh >/dev/null 2>&1 &" ) | crontab - 2>/dev/null
pgrep -f tb-diag-loop.sh >/dev/null || ( nohup ~/tb-diag-loop.sh >/dev/null 2>&1 & )
echo "uplink=$(nmcli -t -f GENERAL.STATE,GENERAL.CONNECTION device show $UPLINK_IFACE 2>/dev/null | tr '\n' ' ')"
echo "hotspot=$(systemctl is-active hostapd 2>/dev/null)"
echo "internet=$(curl -4 -s -o /dev/null -w '%{http_code}' --max-time 7 http://connectivitycheck.gstatic.com/generate_204 2>/dev/null)"
echo "===LOG==="; tail -n 20 ~/tb-diag.log 2>/dev/null
'@

function Do-Check {
  Busy $true 'Checking...'; $script:Pi=$null
  $out=Invoke-Pi $RemoteCheck
  if(-not $script:Pi -or -not $out){
    Set-Ind $rHot $clGrey '--'; Set-Ind $rUp $clGrey '--'; Set-Ind $rNet $clGrey '--'
    $vp.BackColor=(C 253 235 235); $lblV.ForeColor=$clRed
    $lblV.Text="Can't reach the Pi. Is it powered on (~1 min) and is this laptop on the hotspot WiFi? Check Settings for the right address/login."
    Busy $false; return
  }
  if($out -match 'Permission denied|password'){ $vp.BackColor=(C 253 235 235); $lblV.ForeColor=$clRed; $lblV.Text='Login was refused. Open Settings and check the username / password.'; Busy $false; return }
  $up=''; if($out -match 'uplink=(.*)'){ $up=$Matches[1].Trim() }
  $hot=''; if($out -match 'hotspot=(.*)'){ $hot=$Matches[1].Trim() }
  $code=''; if($out -match 'internet=(\d+)'){ $code=$Matches[1] }
  $upName=''; if($up -match 'GENERAL\.CONNECTION:(.+)$'){ $upName=$Matches[1].Trim() }
  $hasUp=($up -match 'STATE:100') -and $upName -and $upName -ne '--'
  $logtail=''; if($out -match '(?s)===LOG===\s*(.*)$'){ $logtail=$Matches[1].Trim() }

  if($hot -eq 'active'){ Set-Ind $rHot $clGreen 'On' } else { Set-Ind $rHot $clRed 'Off' }
  if($hasUp){ Set-Ind $rUp $clGreen $upName } else { Set-Ind $rUp $clAmber 'Not connected' }
  if($code -eq '204'){ Set-Ind $rNet $clGreen 'Online' } elseif($code){ Set-Ind $rNet $clRed "No (code $code)" } else { Set-Ind $rNet $clRed 'No' }

  if($code -eq '204'){ $vp.BackColor=(C 233 247 236); $lblV.ForeColor=$clGreen; $lblV.Text="All good — you are online. Keep this device on the hotspot WiFi." }
  elseif(-not $hasUp){ $vp.BackColor=(C 255 248 225); $lblV.ForeColor=$clAmber; $lblV.Text="The Pi is not joined to any WiFi yet. Scan below, pick the venue network, and press Connect." }
  else { $vp.BackColor=(C 255 248 225); $lblV.ForeColor=$clAmber; $lblV.Text=("Joined '"+$upName+"' but no internet — likely a login page (do the portal step from a spare device) or a 5 GHz network a single radio can't bridge.") }

  $log.Clear(); Logln "Pi at $script:Pi"; Logln "Recent history (logged even offline):"; Logln $logtail
  $lblTime.Text=("Checked "+(Get-Date -Format 'HH:mm:ss'))
  $rep=@("TravelBridge Report - "+(Get-Date),"","Hotspot: "+$rHot.val.Text,"Joined WiFi: "+$rUp.val.Text,"Internet: "+$rNet.val.Text,"","Verdict: "+$lblV.Text,"","--- history ---",$logtail)
  $rep -join "`r`n" | Out-File -FilePath $Report -Encoding utf8
  Busy $false
}

function Do-Scan {
  Busy $true 'Scanning...'
  $out=Invoke-Pi "sudo nmcli -t -f SIGNAL,SECURITY,SSID device wifi list --rescan yes 2>/dev/null | sort -t: -k1 -nr"
  $cbo.Items.Clear()
  if($out){
    $seen=@{}
    foreach($line in ($out -split "`n")){
      $p=$line -split ':',3
      if($p.Count -ge 3 -and $p[2] -and $p[2] -ne $script:Cfg.AP_SSID -and -not $seen.ContainsKey($p[2])){
        $seen[$p[2]]=$true; $sec=if($p[1]){'lock'}else{'open'}; $cbo.Items.Add(("{0}  ({1}%, {2})" -f $p[2],$p[0],$sec)) | Out-Null } } }
  if($cbo.Items.Count){ $cbo.SelectedIndex=0 } else { Logln "No networks found (or Pi unreachable)." }
  Busy $false
}

function Do-Connect {
  if($cbo.SelectedIndex -lt 0){ return }
  $ssid=($cbo.SelectedItem -replace '\s+\(\d+%.*$','')
  Busy $true 'Connecting...'
  $cmd= if($txtP.Text){ "sudo nmcli device wifi connect '$ssid' password '$($txtP.Text)' 2>&1" } else { "sudo nmcli device wifi connect '$ssid' 2>&1" }
  $r=Invoke-Pi $cmd
  Logln ("Connect '$ssid': "+($r -replace "`n",' ').Trim())
  Busy $false; Do-Check
}

# ---------- settings dialog ----------
function Show-Settings {
  $d=New-Object Windows.Forms.Form; $d.Text='TravelBridge — Settings'; $d.Size=New-Object Drawing.Size(420,300)
  $d.StartPosition='CenterParent'; $d.FormBorderStyle='FixedDialog'; $d.MaximizeBox=$false; $d.MinimizeBox=$false; $d.BackColor=$clBg
  function Lab($t,$y){ $l=New-Object Windows.Forms.Label; $l.Text=$t; $l.AutoSize=$true; $l.ForeColor=$clMut; $l.Location=New-Object Drawing.Point(20,$y); $d.Controls.Add($l) }
  Lab 'Pi address(es) — comma separated' 16
  $tH=New-Object Windows.Forms.TextBox; $tH.Size=New-Object Drawing.Size(360,26); $tH.Location=New-Object Drawing.Point(20,38); $tH.Text=($script:Cfg.Hosts -join ', '); $d.Controls.Add($tH)
  Lab 'Login user' 74
  $tU=New-Object Windows.Forms.TextBox; $tU.Size=New-Object Drawing.Size(170,26); $tU.Location=New-Object Drawing.Point(20,96); $tU.Text=$script:Cfg.User; $d.Controls.Add($tU)
  Lab 'Password' 74
  $tPw=New-Object Windows.Forms.TextBox; $tPw.Size=New-Object Drawing.Size(170,26); $tPw.Location=New-Object Drawing.Point(210,96); $tPw.UseSystemPasswordChar=$true; $tPw.Text=(Get-Pw); $d.Controls.Add($tPw)
  $chk=New-Object Windows.Forms.CheckBox; $chk.Text='Set up passwordless login (recommended)'; $chk.AutoSize=$true; $chk.Location=New-Object Drawing.Point(20,140); $chk.Checked=[bool]$script:Cfg.Paired; $d.Controls.Add($chk)
  $note=New-Object Windows.Forms.Label; $note.Text='Installs an SSH key on the Pi so you never type the password again.'; $note.AutoSize=$true; $note.ForeColor=$clGrey; $note.Location=New-Object Drawing.Point(20,164); $d.Controls.Add($note)
  $ok=New-Object Windows.Forms.Button; $ok.Text='Save'; $ok.Size=New-Object Drawing.Size(110,34); $ok.Location=New-Object Drawing.Point(150,210); $ok.FlatStyle='Flat'; $ok.FlatAppearance.BorderSize=0; $ok.BackColor=$clBlue; $ok.ForeColor='White'
  $cancel=New-Object Windows.Forms.Button; $cancel.Text='Cancel'; $cancel.Size=New-Object Drawing.Size(100,34); $cancel.Location=New-Object Drawing.Point(272,210); $cancel.FlatStyle='Flat'; $cancel.BackColor='White'; $cancel.FlatAppearance.BorderColor=$clLine
  $d.Controls.AddRange(@($ok,$cancel)); $d.AcceptButton=$ok; $d.CancelButton=$cancel
  $ok.Add_Click({
    $script:Cfg.Hosts=@(($tH.Text -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $script:Cfg.User=$tU.Text.Trim(); Set-Pw $tPw.Text
    if($chk.Checked -and -not $script:Cfg.Paired){ Pair-Passwordless } else { Save-Cfg }
    $d.DialogResult='OK'; $d.Close() })
  $cancel.Add_Click({ $d.DialogResult='Cancel'; $d.Close() })
  [void]$d.ShowDialog($form)
}

function Pair-Passwordless {
  # generate a key if needed, then install it on the Pi using the password once
  if(-not (Test-Path $KeyFile)){ & ssh-keygen -t ed25519 -f $KeyFile -N '""' -q 2>&1 | Out-Null }
  $pub = (Get-Content "$KeyFile.pub" -Raw).Trim()
  $script:Pi = Find-Pi
  if(-not $script:Pi){ [Windows.Forms.MessageBox]::Show('Pi not reachable — connect to the hotspot first, then try again.','Pairing') | Out-Null; Save-Cfg; return }
  if(-not (Ensure-Ask)){ [Windows.Forms.MessageBox]::Show('Could not build the login helper.','Pairing') | Out-Null; Save-Cfg; return }
  $env:SSH_ASKPASS=$AskExe; $env:SSH_ASKPASS_REQUIRE='force'; $env:DISPLAY='localhost:0'; $env:TB_PW=(Get-Pw)
  try {
    $cmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qxF '$pub' ~/.ssh/authorized_keys 2>/dev/null || echo '$pub' >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; echo PAIRED"
    $r=(& ssh '-o' "UserKnownHostsFile=$KH" '-o' 'StrictHostKeyChecking=accept-new' '-o' 'ConnectTimeout=10' "$($script:Cfg.User)@$($script:Pi)" $cmd 2>&1) | Out-String
    if($r -match 'PAIRED'){ $script:Cfg.Paired=$true; [Windows.Forms.MessageBox]::Show('Passwordless login is set up.','Pairing') | Out-Null }
    else { $script:Cfg.Paired=$false; [Windows.Forms.MessageBox]::Show("Pairing failed:`n$r",'Pairing') | Out-Null }
  } finally { $env:TB_PW=$null; Save-Cfg }
}

$btnCheck.Add_Click({ Do-Check })
$btnScan.Add_Click({ Do-Scan })
$btnConn.Add_Click({ Do-Connect })
$lnkSet.Add_Click({ Show-Settings; Do-Check })
$lnkRep.Add_Click({ if(Test-Path $Report){ Start-Process notepad.exe $Report } })

# ---------- start ----------
Load-Cfg
$form.Add_Shown({ $form.Activate(); if(-not $script:Cfg.Enc -and -not $script:Cfg.Paired){ Show-Settings }; Do-Check })
[void]$form.ShowDialog()
