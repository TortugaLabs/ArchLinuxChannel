<?php
#
# Fix common sequence on shell scripts
#
$begin_marker = '#### start common stuff ####';
$end_marker = '#### stop common stuff ####';

$snippet = file_get_contents(__dir__.'/common.sh');

function fix_file($src) {
  global $begin_marker, $end_marker, $snippet;
  $orig = file_get_contents($src);
  if ($orig === FALSE) return;
  
  $start = strpos($orig,$begin_marker);
  if ($start === FALSE) return;
  $end = strpos($orig,$end_marker,$start);
  if ($end === FALSE) return;
  if ($start > $end) return;
  
  $new = substr($orig,0,$start).
	$begin_marker.PHP_EOL.
	$snippet.
	substr($orig,$end);

  if ($orig != $new) {
    fwrite(STDERR,"Updating: $src\n");
    file_put_contents($src,$new);
  }
}


$directory = new \RecursiveDirectoryIterator('.');
$filter = new \RecursiveCallbackFilterIterator($directory, function ($current, $key, $iterator) {
  // Skip hidden files and directories.
  if ($current->getFilename(){0} === '.') return FALSE;
  if (!$current->isDir()) {
    if (substr($current->getFilename(),-4,4) == '.php') return FALSE;
  }
  
/*  if ($current->isDir()) {
    // Only recurse into intended subdirectories.
    return $current->getFilename() === 'wanted_dirname';
  }
  else {
    // Only consume files of interest.
    return strpos($current->getFilename(), 'wanted_filename') === 0;
  }*/
  return TRUE;
});
$iterator = new \RecursiveIteratorIterator($filter);
foreach ($iterator as $info) {
  fix_file($info->getPathname());
  //echo $info->getPathname().PHP_EOL;
}


