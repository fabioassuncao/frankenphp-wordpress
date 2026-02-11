<?php
/**
 * Plugin Name:     Content Cache Purge
 * Description:     Purge Sidekick cache on post publish. Only active when CACHE_MODE=sidekick.
 * Version:         0.2.0
 */

if (getenv('CACHE_MODE') !== 'sidekick') {
    return;
}

add_action("save_post", function ($id) {
    $post = get_post($id);
    if (!$post || wp_is_post_revision($id) || wp_is_post_autosave($id)) {
        return;
    }

    $purge_path = getenv('PURGE_PATH') ?: '/__cache/purge';
    $purge_key  = getenv('PURGE_KEY') ?: '';

    // Purge the specific page
    $url = get_site_url() . $purge_path . "/" . $post->post_name . "/";
    wp_remote_post($url, [
        "headers" => ["X-WPSidekick-Purge-Key" => $purge_key],
        "timeout" => 5,
        "blocking" => false,
    ]);

    // Purge the home page (frequently affected by new posts)
    $home_url = get_site_url() . $purge_path . "/";
    wp_remote_post($home_url, [
        "headers" => ["X-WPSidekick-Purge-Key" => $purge_key],
        "timeout" => 5,
        "blocking" => false,
    ]);
});
