<?php
/**
 * Plugin Name:     Force URL Rewrite
 * Description:     Required for FrankenPHP to support WordPress pretty permalinks.
 * Version:         0.1.0
 */

add_filter('got_url_rewrite', function() { return true; });
