<?php
header('Content-Type: application/json');
header('Cache-Control: no-cache');
$out = shell_exec("sudo /volume1/docker/simplex/install/www/status.sh 2>/dev/null");
$status = ['simplex-smp'=>'not_found','simplex-xftp'=>'not_found','simplex-turn'=>'not_found'];
foreach (explode("\n", trim($out)) as $line) {
    $parts = explode(' ', trim(str_replace('/','',$line)));
    if (count($parts) === 2) $status[$parts[0]] = $parts[1];
}
echo json_encode($status);