<link rel="stylesheet" type="text/css" href="kismet_sql.css?ver=1.2">
<script src="sorttable.js"></script>
<?php
   class kismet_sqlDB extends SQLite3 {
      function __construct() {
         $this->open('/var/local/kismet.sql3');
      }
   }
   $db = new kismet_sqlDB();
   if(!$db) {
      echo $db->lastErrorMsg();
   }

   $db->busyTimeout(10000);

   $page = $_SERVER['PHP_SELF'];
   $sec = "30";
   header("Refresh: $sec; url=$page");

   $timezone=10;

   # Interval definition in minutes
   $int1=1;
   $int2=2;
   $int3=5;
   $int4=6;

   $maxint=$int4;

   # Counters
   $int1cnt=0;
   $int2cnt=0;
   $int3cnt=0;
   $int4cnt=0;
   
   # Colors
   $int1col = "#22ff66";
   $int2col = "#40d984";
   $int3col = "#b0b040";
   $int4col = "#c80000";

   # Interval font styles
   $int0style = '<b>';
   $int0styleend = '</b>';
   $int1style = '';
   $int1styleend = '';
   $int2style = '';
   $int2styleend = '';
   $int3style = '<i>';
   $int3styleend = '</i>';
   $int4style = '<s><i>';
   $int4styleend = '</i></s>';

   date_default_timezone_set('Australia/Brisbane');

   # Header
   print '<table class="sortable stackable ui selectable inverted compact table">';
   print '<tr><th>Common Name</th><th>MAC Address</th><th>BSSID</th><th>Type</th><th>Manufacturer</th><th style="text-align:right">Signal</th><th>First Time</th><th>Duration</th><th>Last Seen</th><th>Previously Seen</th></tr>';

   $sql =<<<EOF
	select t1.mac, t1.ssid, t1.devtype, t1.manuf, t1.signal, datetime(t1.firsttime + $timezone*3600, 'unixepoch') as 'firsttime', datetime(t1.lasttime + $timezone*3600, 'unixepoch') as 'lasttime', time(datetime(t1.lasttime - t1.firsttime)) as 'duration', datetime(t1.previoustime +$timezone*3600, 'unixepoch') as 'previously seen', t1.previoustime as 'previously seen raw', t1.commonname as 'common name' from client t1 where t1.lasttime > (julianday('now') - 2440587.5)*86400.0 - $maxint*60 order by t1.devtype desc, t1.firsttime desc;
EOF;

   $ret = $db->query($sql);
   while($row = $ret->fetchArray(SQLITE3_ASSOC) ) {

	   # Calculate duration
	   $lasttime = strtotime($row['lasttime']);
	   $firsttime = strtotime($row['firsttime']);
	   $duration = $lasttime - $firsttime; 
	   $durationdays = (int)($duration/86400);
	   $durationhrs = (int)(($duration - ($durationdays * 86400))/3600);
	   $durationmins = (int)(($duration - ($durationdays * 86400))/60%60);
	   $durationsecs = $duration%60;
	   $durationstr = sprintf('%1dD %d:%02d:%02d', $durationdays, $durationhrs, $durationmins, $durationsecs);

	   # Calculate time since last seen
	   $interval = time() - $lasttime;
	   $intervalmins = (int)(($interval)/60);
	   $intervalsecs = $interval - $intervalmins*60;
	   $intervalstr = sprintf('%1d:%02d', $intervalmins, $intervalsecs);

	   # Calculate time since previously seen
	   if (!empty($row['previously seen raw'])) { 
   	   	$prevago = time() - strtotime($row['previously seen']); 
	   	$prevagodays = (int)($prevago/86400);
	   	$prevagohrs = (int)(($prevago - ($prevagodays * 86400))/3600);
	   	$prevagomins = (int)(($prevago - ($prevagodays * 86400))/60%60);
	   	$prevagosecs = $prevago%60;
		$prevagostr = sprintf('%1dD %d:%02d:%02d', $prevagodays, $prevagohrs, $prevagomins, $prevagosecs);
	   } else { 
	        $prevagostr = '';
	   }

	   # Scale row intensity based on time since last seen 
	   $colintensity = dechex(255 - (180 * $interval / $maxint/ 60));

	   # Scale signal color based on singal strength
	   $sigintensity = dechex(255 - (254 * (100 + $row['signal']) / 100));
	   $sigintensity2 = dechex(254 * (100 + $row['signal']) / 100);

	   $color = "#".$colintensity.$colintensity.$colintensity;
	   $sigcolor = "#".$sigintensity.$sigintensity2."00";

	   $ssid = $row['ssid'];
	   if ($row['devtype'] == 'Wi-Fi AP') {		# Access Point
		   $bgcolor = "darkslategray";
		   $ssid = "";
	   } elseif ($row['devtype'] == 'BTLE') {	# Bluetooth Device
		   $bgcolor = "#000040";
		   $sigcolor = $color;
		   $ssid = "";
	   } else {
		   $bgcolor = "black";
	   }

	   # Set style and device counter depending on time since last seen
	   if ($interval <= $int1*30) {
		   ++$int1cnt;
		   $style=$int0style;
		   $styleend=$int0styleend;
	  } elseif ($interval <= $int1*60) {
		   ++$int1cnt;
		   $style=$int1style;
		   $styleend=$int1styleend;
	   } elseif ($interval <= $int2*60) {
		   ++$int2cnt;
		   $style=$int2style;
		   $styleend=$int2styleend;

	   } elseif ($interval <= $int3*60) {
		   ++$int3cnt;
		   $style=$int3style;
		   $styleend=$int3styleend;
	   } else {
		   ++$int4cnt;
		   $style=$int4style;
		   $styleend=$int4styleend;
	   }

	   # Row output
	   print '<tr><td bgcolor='.$bgcolor.'><font color='.$color.'>'.$style.$row['common name'].$styleend.'</font></td>';
	   print '<td bgcolor='.$bgcolor.'><font color='.$color.'>'.$style.$row['mac'].$styleend.'</font></td>';
	   print '<td bgcolor='.$bgcolor.'><font color='.$color.'>'.$style.$ssid.$styleend.'</font></td>'; 
	   print '<td bgcolor='.$bgcolor.'><font color='.$color.'>'.$style.$row['devtype'].$styleend.'</font></td>'; 
	   print '<td bgcolor='.$bgcolor.'><font color='.$color.'>'.$style.$row['manuf'].$styleend.'</font></td>';
	   print '<td style="text-align:right"; bgcolor='.$bgcolor.'><font color='.$sigcolor.'>'.$style.$row['signal'].$styleend.'</font></td>';
	   print '<td bgcolor='.$bgcolor.'><font color='.$color.'>'.$style.$row['firsttime'].$styleend.'</font></td>';
	   print '<td bgcolor='.$bgcolor.'><font color='.$color.'>'.$style.$durationstr.$styleend.'</font></td>';
	   print '<td style="text-align:center"; bgcolor='.$bgcolor.'><font color='.$color.'>'.$style.$intervalstr.$styleend.'</font></td>';
	   print '<td style="text-align:center"; bgcolor='.$bgcolor.'><font color='.$color.'>'.$style.$prevagostr.$styleend.'</font></td></tr>';
   }
   print '</table>';

   # Summary
   print '<p><font color="white">Total Devices: '.($int1cnt+$int2cnt+$int3cnt+$int4cnt).' (Last '.$maxint.' minutes)<br>';
   print '<font color='.$int1col.'>'.$int1style.'Active ('.$int1cnt.' Devices)'.$inst1styleend.'</font><br>';
   print '<font color='.$int2col.'>'.$inst2style.'>'.$int1.' minutes ('.$int2cnt.' Devices, '.($int1cnt+$int2cnt).' cumulative)'.$int2styleend.'</font><br>';
   print '<font color='.$int3col.'>'.$int3style.'>'.$int2.' minutes ('.$int3cnt.' Devices, '.($int1cnt+$int2cnt+$int3cnt).' cumulative)'.$int3styleend.'</font><br>';
   print '<font color='.$int4col.'>'.$int4style.'>'.$int3.' minutes ('.$int4cnt.' Devices, '.($int1cnt+$int2cnt+$int3cnt+$int4cnt).' cumulative)'.$int4styleend.'</font></p>';
   
   $db->close();
?>
