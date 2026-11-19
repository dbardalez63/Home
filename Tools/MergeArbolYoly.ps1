# Line-based merge of ArbolYoly.txt into Ancestry GEDCOM (avoids heavy regex)
$ErrorActionPreference = 'Stop'
$baseGed = 'E:\Downloads\Maria Adela Rodriguez.ged'
$backup = 'E:\Downloads\Maria-Adela-Rodriguez-Ancestry-original.ged'
$outGed = 'E:\Downloads\Maria-Adela-Rodriguez-Yoly.ged'
$projectGed = 'C:\Users\diego\source\repos\FamiliaRodriguez\Data\Gedcom\Maria-Adela-Rodriguez.ged'

if (-not (Test-Path $backup)) { Copy-Item $baseGed $backup -Force }

$lines = [System.Collections.Generic.List[string]]::new()
Get-Content $baseGed | ForEach-Object { $lines.Add($_) }

function Find-IndiIndex([string]$id) {
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -eq "0 @$id@ INDI") { return $i }
  }
  return -1
}

function Find-RecordEnd([int]$start) {
  for ($i = $start + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^0 ') { return $i }
  }
  return $lines.Count
}

function Insert-AfterIndiHeader([string]$id, [string[]]$newLines) {
  $idx = Find-IndiIndex $id
  if ($idx -lt 0) { return }
  $lines.InsertRange($idx + 1, $newLines)
}

function Ensure-LineInIndi([string]$id, [string]$exactLine) {
  $idx = Find-IndiIndex $id
  if ($idx -lt 0) { return }
  $end = Find-RecordEnd $idx
  for ($i = $idx; $i -lt $end; $i++) {
    if ($lines[$i] -eq $exactLine) { return }
  }
  $lines.Insert($idx + 1, $exactLine)
}

function Set-FirstEvent([string]$id, [string]$tag, [string]$date, [string]$plac) {
  $idx = Find-IndiIndex $id
  if ($idx -lt 0) { return }
  $end = Find-RecordEnd $idx
  $eventIdx = -1
  for ($i = $idx + 1; $i -lt $end; $i++) {
    if ($lines[$i] -eq "1 $tag") { $eventIdx = $i; break }
  }
  if ($eventIdx -lt 0) {
    $insert = [System.Collections.Generic.List[string]]::new()
    $insert.Add("1 $tag")
    if ($date) { $insert.Add("2 DATE $date") }
    if ($plac) { $insert.Add("2 PLAC $plac") }
    $lines.InsertRange($idx + 1, $insert)
    return
  }
  # update first DATE/PLAC under this event until next level-1/0
  $dateSet = $false; $placSet = $false
  $j = $eventIdx + 1
  while ($j -lt $lines.Count -and $lines[$j] -match '^[2-9] ') {
    if ($date -and $lines[$j] -match '^2 DATE ' -and -not $dateSet) {
      $lines[$j] = "2 DATE $date"; $dateSet = $true
    }
    if ($plac -and $lines[$j] -match '^2 PLAC ' -and -not $placSet) {
      $lines[$j] = "2 PLAC $plac"; $placSet = $true
    }
    $j++
  }
  $insertAt = $eventIdx + 1
  if ($date -and -not $dateSet) { $lines.Insert($insertAt, "2 DATE $date"); $insertAt++; if ($plac -and -not $placSet) { $lines.Insert($insertAt, "2 PLAC $plac") } }
  elseif ($plac -and -not $placSet) { $lines.Insert($insertAt, "2 PLAC $plac") }
}

function Add-Note([string]$id, [string]$note) {
  Ensure-LineInIndi $id ("1 NOTE $note")
}

# Patches from ArbolYoly.txt
Set-FirstEvent 'I122815866172' 'BIRT' '11 Aug 1877' 'Calzada, Moyobamba, San Martin, Peru'
Set-FirstEvent 'I122815866172' 'DEAT' '6 Jun 1944' 'Iquitos, Loreto, Peru'
Add-Note 'I122815866172' 'ArbolYoly.txt: N 11.08.1877 Calzada Moyobamba; F 06.06.1944 Iquitos.'

Set-FirstEvent 'I122477351804' 'DEAT' '9 Mar 1993' 'Iquitos, Loreto, Peru'
Add-Note 'I122477351804' 'ArbolYoly.txt: F 09.03.1993. Parejas: Mercedes Diaz Piadoso, Francisca Rodriguez Sifuentes, Tesalia Torres.'

Add-Note 'I122477351500' 'ArbolYoly.txt: N 04.04.1905 Iquitos; F 13.02.1950 Iquitos (44 anos).'
Add-Note 'I122815865828' 'ArbolYoly.txt: nacido Odilon Alvarez Gonzalez (madre soltera). F 06.12.1940 Hospital Santa Rosa de Itaya (cancer de colon).'
Add-Note 'I122815865891' 'ArbolYoly.txt: Rosalia Cifuentes Vasquez (costurera). Medio hermano Emilio Pinedo Vasquez (Yurimaguas).'
Add-Note 'I122815866090' 'ArbolYoly.txt cuestiona identidad alemana. Suegro tambien citado como Vicente Rodriguez Riva (F 20.02.1919 tuberculosis).'

Set-FirstEvent 'I122815872768' 'BIRT' 'ABT 1939' 'Iquitos, Loreto, Peru'
Set-FirstEvent 'I122815872768' 'DEAT' '18 May 1940' 'Iquitos, Loreto, Peru'
Add-Note 'I122815872768' 'ArbolYoly.txt: N ~1939; F 18.05.1940 (~2 anos).'

Set-FirstEvent 'I122815872567' 'BIRT' '25 May 1944' 'Iquitos, Loreto, Peru'
Set-FirstEvent 'I122815872689' 'BIRT' '18 Jun 1942' 'Iquitos, Loreto, Peru'

Ensure-LineInIndi 'I122815866172' '1 FAMC @FYOLY02@'
Ensure-LineInIndi 'I122815865891' '1 FAMC @FYOLY03@'

# Add children to F18
$f18 = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq '0 @F18@ FAM') { $f18 = $i; break } }
if ($f18 -ge 0) {
  $end = Find-RecordEnd $f18
  $existing = ($lines.GetRange($f18, $end - $f18) | Where-Object { $_ -match '^1 CHIL ' }) -join "`n"
  foreach ($cid in @('IYOLY014','IYOLY015','IYOLY016','IYOLY017','IYOLY009','IYOLY018','IYOLY022','I122815870791')) {
    $line = "1 CHIL @$cid@"
    if ($existing -notmatch [regex]::Escape($line)) {
      $lines.Insert($end, $line)
      $end++
    }
  }
}

# Remove trailing TRLR
while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -match '^\s*$') { $lines.RemoveAt($lines.Count - 1) }
if ($lines[$lines.Count - 1] -eq '0 TRLR') { $lines.RemoveAt($lines.Count - 1) }

$append = @(
'0 @IYOLY001@ INDI',
'1 NAME Vicente /Rodriguez Riva/',
'2 GIVN Vicente',
'2 SURN Rodriguez Riva',
'1 SEX M',
'1 FAMS @FYOLY01@',
'1 DEAT',
'2 DATE 20 Feb 1919',
'2 PLAC Iquitos, Loreto, Peru',
'1 NOTE Moyobamba. Tuberculosis. Citado en ArbolYoly.txt como suegro de Francisca / posible padre de Telesforo.',
'0 @IYOLY002@ INDI',
'1 NAME Juan de la Cruz /Fernandez/',
'2 GIVN Juan de la Cruz',
'2 SURN Fernandez',
'1 SEX M',
'1 FAMS @FYOLY02@',
'1 BIRT',
'2 DATE 1852',
'2 PLAC Calzada, Moyobamba, San Martin, Peru',
'1 NOTE Padre de Susana Fernandez Acosta. Fuente ArbolYoly.txt.',
'0 @IYOLY003@ INDI',
'1 NAME Adelaida /Acosta Cardenas/',
'2 GIVN Adelaida',
'2 SURN Acosta Cardenas',
'1 SEX F',
'1 FAMS @FYOLY02@',
'1 BIRT',
'2 DATE 1854',
'2 PLAC Calzada, Moyobamba, San Martin, Peru',
'1 DEAT',
'2 DATE 1942',
'1 NOTE Madre de Susana Fernandez Acosta. Fuente ArbolYoly.txt.',
'0 @IYOLY004@ INDI',
'1 NAME Hipolito /Cifuentes/',
'2 GIVN Hipolito',
'2 SURN Cifuentes',
'1 SEX M',
'1 FAMS @FYOLY03@',
'1 NOTE Abuelo materno de Francisca (padre de Rosalia). Fuente ArbolYoly.txt.',
'0 @IYOLY005@ INDI',
'1 NAME Maria Francisca de la O. /Vasquez Ruiz/',
'2 GIVN Maria Francisca de la O.',
'2 SURN Vasquez Ruiz',
'1 SEX F',
'1 FAMC @FYOLY04@',
'1 FAMS @FYOLY03@',
'1 BIRT',
'2 DATE 19 Dec 1841',
'2 PLAC San Martin, Peru',
'1 NOTE Abuela materna de Francisca. Fuente ArbolYoly.txt.',
'0 @IYOLY006@ INDI',
'1 NAME Alejandro /Vasquez/',
'2 GIVN Alejandro',
'2 SURN Vasquez',
'1 SEX M',
'1 FAMS @FYOLY04@',
'0 @IYOLY007@ INDI',
'1 NAME Maria Faustina /Ruiz/',
'2 GIVN Maria Faustina',
'2 SURN Ruiz',
'1 SEX F',
'1 FAMS @FYOLY04@',
'0 @IYOLY008@ INDI',
'1 NAME Emilio /Pinedo Vasquez/',
'2 GIVN Emilio',
'2 SURN Pinedo Vasquez',
'1 SEX M',
'1 NOTE Medio hermano de Rosalia; vivio en Yurimaguas. Fuente ArbolYoly.txt.',
'0 @IYOLY009@ INDI',
'1 NAME Maria Adela /Rodriguez Fernandez/',
'2 GIVN Maria Adela',
'2 SURN Rodriguez Fernandez',
'1 SEX F',
'1 FAMC @F18@',
'1 FAMS @FYOLY05@',
'1 BIRT',
'2 DATE 13 Mar 1908',
'2 PLAC Peru',
'1 NOTE Hermana de Telesforo. Fecha texto 13.93.1908 interpretada 13.03.1908.',
'0 @IYOLY010@ INDI',
'1 NAME Toribio /Campos/',
'2 GIVN Toribio',
'2 SURN Campos',
'1 SEX M',
'1 FAMS @FYOLY05@',
'0 @IYOLY011@ INDI',
'1 NAME Maritza /Campos Rodriguez/',
'2 GIVN Maritza',
'2 SURN Campos Rodriguez',
'1 SEX F',
'1 FAMC @FYOLY05@',
'0 @IYOLY012@ INDI',
'1 NAME Mariela /Campos Rodriguez/',
'2 GIVN Mariela',
'2 SURN Campos Rodriguez',
'1 SEX F',
'1 FAMC @FYOLY05@',
'0 @IYOLY013@ INDI',
'1 NAME Milena /Campos Rodriguez/',
'2 GIVN Milena',
'2 SURN Campos Rodriguez',
'1 SEX F',
'1 FAMC @FYOLY05@',
'0 @IYOLY014@ INDI',
'1 NAME Juan de la Cruz /Rodriguez Fernandez/',
'2 GIVN Juan de la Cruz',
'2 SURN Rodriguez Fernandez',
'1 SEX M',
'1 FAMC @F18@',
'1 BIRT',
'2 DATE 13 Jan 1893',
'0 @IYOLY015@ INDI',
'1 NAME Teofilo /Rodriguez Fernandez/',
'2 GIVN Teofilo',
'2 SURN Rodriguez Fernandez',
'1 SEX M',
'1 FAMC @F18@',
'1 BIRT',
'2 DATE 1896',
'1 DEAT',
'2 DATE 26 Jul 1968',
'0 @IYOLY016@ INDI',
'1 NAME Julio Cesar /Rodriguez Fernandez/',
'2 GIVN Julio Cesar',
'2 SURN Rodriguez Fernandez',
'1 SEX M',
'1 FAMC @F18@',
'1 BIRT',
'2 DATE 1901',
'1 DEAT',
'2 DATE 12 Aug 1942',
'1 NOTE Heroe campana 1941. Fuente ArbolYoly.txt.',
'0 @IYOLY017@ INDI',
'1 NAME Telesforo /Rodriguez Fernandez/',
'2 GIVN Telesforo',
'2 SURN Rodriguez Fernandez',
'1 SEX M',
'1 FAMC @F18@',
'1 BIRT',
'2 DATE 1903',
'1 NOTE Hermano homonimo de Telesforo (N 1903). Fuente ArbolYoly.txt.',
'0 @IYOLY018@ INDI',
'1 NAME Eugenia Ysabel /Rodriguez Fernandez/',
'2 GIVN Eugenia Ysabel',
'2 SURN Rodriguez Fernandez',
'1 SEX F',
'1 FAMC @F18@',
'1 FAMS @FYOLY06@',
'1 BIRT',
'2 DATE 20 Mar 1916',
'0 @IYOLY019@ INDI',
'1 NAME Luis Jesus /Barreiro/',
'2 GIVN Luis Jesus',
'2 SURN Barreiro',
'1 SEX M',
'1 FAMS @FYOLY06@',
'1 NOTE Argentino. Fuente ArbolYoly.txt.',
'0 @IYOLY020@ INDI',
'1 NAME Leonor Ines /Barreiro Rodriguez/',
'2 GIVN Leonor Ines',
'2 SURN Barreiro Rodriguez',
'1 SEX F',
'1 FAMC @FYOLY06@',
'1 FAMS @FYOLY07@',
'1 BIRT',
'2 DATE 11 Aug 1944',
'2 PLAC Buenos Aires, Argentina',
'0 @IYOLY021@ INDI',
'1 NAME Sonia /Dios Barreiro/',
'2 GIVN Sonia',
'2 SURN Dios Barreiro',
'1 SEX F',
'1 FAMC @FYOLY07@',
'0 @IYOLY022@ INDI',
'1 NAME Exilda /Rodriguez Fernandez/',
'2 GIVN Exilda',
'2 SURN Rodriguez Fernandez',
'1 SEX F',
'1 FAMC @F18@',
'1 FAMS @FYOLY08@',
'1 BIRT',
'2 DATE 17 Apr 1918',
'1 DEAT',
'2 DATE 24 Sep 2003',
'0 @IYOLY023@ INDI',
'1 NAME Luis /Cortez Zelaya/',
'2 GIVN Luis',
'2 SURN Cortez Zelaya',
'1 SEX M',
'1 FAMS @FYOLY08@',
'0 @IYOLY024@ INDI',
'1 NAME Consuelo /Cortez Rodriguez/',
'2 GIVN Consuelo',
'2 SURN Cortez Rodriguez',
'1 SEX F',
'1 FAMC @FYOLY08@',
'0 @IYOLY025@ INDI',
'1 NAME Luis /Cortez Rodriguez/',
'2 GIVN Luis',
'2 SURN Cortez Rodriguez',
'1 SEX M',
'1 FAMC @FYOLY08@',
'0 @FYOLY01@ FAM',
'1 HUSB @IYOLY001@',
'1 WIFE @I122815866172@',
'1 NOTE Union sugerida por ArbolYoly.txt; coexiste con Vicent Gerhart.',
'0 @FYOLY02@ FAM',
'1 HUSB @IYOLY002@',
'1 WIFE @IYOLY003@',
'1 CHIL @I122815866172@',
'0 @FYOLY03@ FAM',
'1 HUSB @IYOLY004@',
'1 WIFE @IYOLY005@',
'1 CHIL @I122815865891@',
'0 @FYOLY04@ FAM',
'1 HUSB @IYOLY006@',
'1 WIFE @IYOLY007@',
'1 CHIL @IYOLY005@',
'0 @FYOLY05@ FAM',
'1 HUSB @IYOLY010@',
'1 WIFE @IYOLY009@',
'1 CHIL @IYOLY011@',
'1 CHIL @IYOLY012@',
'1 CHIL @IYOLY013@',
'0 @FYOLY06@ FAM',
'1 HUSB @IYOLY019@',
'1 WIFE @IYOLY018@',
'1 CHIL @IYOLY020@',
'0 @FYOLY07@ FAM',
'1 WIFE @IYOLY020@',
'1 CHIL @IYOLY021@',
'0 @FYOLY08@ FAM',
'1 HUSB @IYOLY023@',
'1 WIFE @IYOLY022@',
'1 CHIL @IYOLY024@',
'1 CHIL @IYOLY025@',
'0 TRLR'
)

foreach ($l in $append) { $lines.Add($l) }

$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines($outGed, $lines, $utf8)
Copy-Item $outGed $projectGed -Force

$indi = ($lines | Where-Object { $_ -match '^0 @I[^@]+@ INDI' }).Count
$fam = ($lines | Where-Object { $_ -match '^0 @F[^@]+@ FAM' }).Count
Write-Output "Wrote $outGed"
Write-Output "INDI=$indi FAM=$fam lines=$($lines.Count) size=$((Get-Item $outGed).Length)"
