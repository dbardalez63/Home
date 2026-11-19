<?php
/**
 * Copia este archivo a config.php y cambia la contraseña.
 * config.php no debe subirse a repositorios públicos.
 */
return [
    // Contraseña para ver los logs (cámbiala)
    'password' => 'CambiaEstaClave',

    // Segundos de sesión
    'session_ttl' => 28800,

    // Preferible fuera del Document Root (lo configura install.sh):
    // '/volume1/@appdata/familia-accesos/recent.json'
    'data_file' => '/volume1/@appdata/familia-accesos/recent.json',
];
