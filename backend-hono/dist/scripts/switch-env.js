import fs from 'fs';
import path from 'path';
import mysql from 'mysql2/promise';
// Find config file
function findConfigFile() {
    const candidates = [
        path.resolve('./ecosystem.config.json'),
        path.resolve('../ecosystem.config.json'),
        path.resolve(process.cwd(), 'ecosystem.config.json'),
        path.resolve(process.cwd(), '../ecosystem.config.json'),
    ];
    for (const p of candidates) {
        if (fs.existsSync(p))
            return p;
    }
    throw new Error('Could not find ecosystem.config.json in project root or backend-hono!');
}
function updateEnvFile(filePath, updates) {
    if (!fs.existsSync(filePath)) {
        console.warn(`File not found, creating new: ${filePath}`);
        const content = Object.entries(updates)
            .map(([k, v]) => `${k}=${v}`)
            .join('\n');
        fs.writeFileSync(filePath, content, 'utf8');
        return;
    }
    let content = fs.readFileSync(filePath, 'utf8');
    for (const [key, value] of Object.entries(updates)) {
        const regex = new RegExp(`^${key}=.*$`, 'm');
        if (regex.test(content)) {
            content = content.replace(regex, `${key}=${value}`);
        }
        else {
            content += `\n${key}=${value}`;
        }
    }
    fs.writeFileSync(filePath, content, 'utf8');
}
function readEnvVar(filePath, key) {
    if (!fs.existsSync(filePath))
        return null;
    const content = fs.readFileSync(filePath, 'utf8');
    const match = content.match(new RegExp(`^${key}=(.*)$`, 'm'));
    return match ? match[1].trim() : null;
}
async function main() {
    const args = process.argv.slice(2);
    const configPath = findConfigFile();
    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    let targetProfileKey = config.activeProfile || 'local';
    let customDomain = null;
    for (const arg of args) {
        if (arg.startsWith('--domain=')) {
            customDomain = arg.replace('--domain=', '').trim().replace(/\/+$/, '');
        }
        else if (arg.startsWith('http://') || arg.startsWith('https://')) {
            customDomain = arg.trim().replace(/\/+$/, '');
        }
        else if (config.profiles[arg]) {
            targetProfileKey = arg;
        }
    }
    console.log('\n🔄 ─────────────────────────────────────────────────────────────');
    console.log('   Iter / Coil Environment & Domain Synchronization');
    console.log('─────────────────────────────────────────────────────────────\n');
    let profile;
    if (customDomain) {
        console.log(`🌐 Custom domain supplied: ${customDomain}`);
        profile = {
            name: `Custom Domain (${customDomain})`,
            appUrl: customDomain,
            storagePublicUrl: `${customDomain}/uploads`,
            databaseUrl: config.profiles[targetProfileKey]?.databaseUrl || 'mysql://root:1842@localhost:3306/iter_db',
            flutterApiBaseUrl: `${customDomain}/api/v1`,
        };
        config.profiles['custom'] = profile;
        targetProfileKey = 'custom';
    }
    else {
        profile = config.profiles[targetProfileKey];
        if (!profile) {
            console.error(`❌ Unknown profile: "${targetProfileKey}". Available profiles: ${Object.keys(config.profiles).join(', ')}`);
            process.exit(1);
        }
    }
    console.log(`📌 Applying Profile: [${targetProfileKey.toUpperCase()}] - ${profile.name}`);
    console.log(`   • Server App URL:       ${profile.appUrl}`);
    console.log(`   • Media Storage URL:    ${profile.storagePublicUrl}`);
    console.log(`   • Flutter API Base URL: ${profile.flutterApiBaseUrl}`);
    console.log(`   • Database URL:         ${profile.databaseUrl.replace(/:[^:@]+@/, ':****@')}\n`);
    // 1. Determine Backend and Flutter .env paths
    const backendDir = fs.existsSync('./package.json') && JSON.parse(fs.readFileSync('./package.json', 'utf8')).name === 'iter-backend-hono'
        ? path.resolve('.')
        : path.resolve('./backend-hono');
    const rootDir = path.resolve(backendDir, '..');
    const backendEnvPath = path.join(backendDir, '.env');
    const flutterEnvPath = path.join(rootDir, '.env');
    // Read previous storage URL before updating
    const previousStorageUrl = readEnvVar(backendEnvPath, 'STORAGE_PUBLIC_URL');
    // 2. Update Backend .env
    console.log(`📝 Updating backend .env (${backendEnvPath})...`);
    updateEnvFile(backendEnvPath, {
        APP_URL: profile.appUrl,
        STORAGE_PUBLIC_URL: profile.storagePublicUrl,
        DATABASE_URL: profile.databaseUrl,
    });
    console.log('   ✅ Backend .env updated.');
    // 3. Update Flutter .env
    console.log(`📱 Updating Flutter .env (${flutterEnvPath})...`);
    updateEnvFile(flutterEnvPath, {
        API_BASE_URL: profile.flutterApiBaseUrl,
    });
    console.log('   ✅ Flutter .env updated.');
    // 4. Save activeProfile in ecosystem.config.json
    config.activeProfile = targetProfileKey;
    fs.writeFileSync(configPath, JSON.stringify(config, null, 2), 'utf8');
    const altConfigPath = path.join(rootDir, 'ecosystem.config.json');
    if (fs.existsSync(altConfigPath) && altConfigPath !== configPath) {
        fs.writeFileSync(altConfigPath, JSON.stringify(config, null, 2), 'utf8');
    }
    // 5. Database URL Search & Replace
    const oldPrefixes = new Set();
    if (previousStorageUrl && previousStorageUrl !== profile.storagePublicUrl) {
        oldPrefixes.add(previousStorageUrl);
    }
    // Common prefixes
    oldPrefixes.add('http://192.168.1.194:3000/uploads');
    oldPrefixes.add('http://localhost:3000/uploads');
    for (const legacy of config.legacyStoragePrefixes || []) {
        oldPrefixes.add(legacy);
    }
    // Remove the current new storage URL from old prefixes list
    oldPrefixes.delete(profile.storagePublicUrl);
    console.log(`\n🗄️ Checking MySQL Database for URL replacements...`);
    console.log(`   Target New Media URL: ${profile.storagePublicUrl}`);
    console.log(`   Old Prefixes to replace:`, Array.from(oldPrefixes));
    try {
        const connection = await mysql.createConnection(profile.databaseUrl);
        console.log('   ✅ Connected to MySQL successfully.\n');
        let totalReplacements = 0;
        for (const oldPrefix of oldPrefixes) {
            if (!oldPrefix || oldPrefix.length < 5)
                continue;
            console.log(`   🔎 Scanning & replacing: "${oldPrefix}" ➡️ "${profile.storagePublicUrl}"`);
            // A. Users (avatar_url, cover_url)
            const [uRes1] = await connection.execute(`UPDATE users SET avatar_url = REPLACE(avatar_url, ?, ?) WHERE avatar_url LIKE ?`, [oldPrefix, profile.storagePublicUrl, `%${oldPrefix}%`]);
            const [uRes2] = await connection.execute(`UPDATE users SET cover_url = REPLACE(cover_url, ?, ?) WHERE cover_url LIKE ?`, [oldPrefix, profile.storagePublicUrl, `%${oldPrefix}%`]);
            const userUpdates = (uRes1.affectedRows || 0) + (uRes2.affectedRows || 0);
            if (userUpdates > 0)
                console.log(`      • users: updated ${userUpdates} fields`);
            // B. Posts (author_avatar)
            const [pRes1] = await connection.execute(`UPDATE posts SET author_avatar = REPLACE(author_avatar, ?, ?) WHERE author_avatar LIKE ?`, [oldPrefix, profile.storagePublicUrl, `%${oldPrefix}%`]);
            if (pRes1.affectedRows > 0)
                console.log(`      • posts (author_avatar): updated ${pRes1.affectedRows} rows`);
            // Posts JSON arrays (image_urls, video_urls)
            try {
                const [postsToFix] = await connection.execute(`SELECT id, image_urls, video_urls FROM posts WHERE CAST(image_urls AS CHAR) LIKE ? OR CAST(video_urls AS CHAR) LIKE ?`, [`%${oldPrefix}%`, `%${oldPrefix}%`]);
                let postMediaUpdates = 0;
                for (const row of postsToFix) {
                    let imgUrls = Array.isArray(row.image_urls) ? row.image_urls : [];
                    let vidUrls = Array.isArray(row.video_urls) ? row.video_urls : [];
                    if (typeof row.image_urls === 'string') {
                        try {
                            imgUrls = JSON.parse(row.image_urls);
                        }
                        catch (_) { }
                    }
                    if (typeof row.video_urls === 'string') {
                        try {
                            vidUrls = JSON.parse(row.video_urls);
                        }
                        catch (_) { }
                    }
                    const newImgs = imgUrls.map((u) => (typeof u === 'string' ? u.replace(oldPrefix, profile.storagePublicUrl) : u));
                    const newVids = vidUrls.map((u) => (typeof u === 'string' ? u.replace(oldPrefix, profile.storagePublicUrl) : u));
                    await connection.execute(`UPDATE posts SET image_urls = ?, video_urls = ? WHERE id = ?`, [JSON.stringify(newImgs), JSON.stringify(newVids), row.id]);
                    postMediaUpdates++;
                }
                if (postMediaUpdates > 0) {
                    console.log(`      • posts (image_urls / video_urls): updated ${postMediaUpdates} posts`);
                }
            }
            catch (postJsonErr) {
                console.warn('      ⚠️ Note on posts media JSON update:', postJsonErr.message);
            }
            // C. Comments (author_avatar)
            const [cRes] = await connection.execute(`UPDATE comments SET author_avatar = REPLACE(author_avatar, ?, ?) WHERE author_avatar LIKE ?`, [oldPrefix, profile.storagePublicUrl, `%${oldPrefix}%`]);
            if (cRes.affectedRows > 0)
                console.log(`      • comments: updated ${cRes.affectedRows} rows`);
            // D. Events (cover_image_url)
            const [eRes] = await connection.execute(`UPDATE events SET cover_image_url = REPLACE(cover_image_url, ?, ?) WHERE cover_image_url LIKE ?`, [oldPrefix, profile.storagePublicUrl, `%${oldPrefix}%`]);
            if (eRes.affectedRows > 0)
                console.log(`      • events: updated ${eRes.affectedRows} rows`);
            // E. Stories (image_url, video_url, author_avatar)
            const [sRes1] = await connection.execute(`UPDATE stories SET image_url = REPLACE(image_url, ?, ?) WHERE image_url LIKE ?`, [oldPrefix, profile.storagePublicUrl, `%${oldPrefix}%`]);
            const [sRes2] = await connection.execute(`UPDATE stories SET video_url = REPLACE(video_url, ?, ?) WHERE video_url LIKE ?`, [oldPrefix, profile.storagePublicUrl, `%${oldPrefix}%`]);
            const [sRes3] = await connection.execute(`UPDATE stories SET author_avatar = REPLACE(author_avatar, ?, ?) WHERE author_avatar LIKE ?`, [oldPrefix, profile.storagePublicUrl, `%${oldPrefix}%`]);
            const storyUpdates = (sRes1.affectedRows || 0) + (sRes2.affectedRows || 0) + (sRes3.affectedRows || 0);
            if (storyUpdates > 0)
                console.log(`      • stories: updated ${storyUpdates} fields`);
            // F. Messages (image_url, video_url, voice_url)
            const [mRes1] = await connection.execute(`UPDATE messages SET image_url = REPLACE(image_url, ?, ?) WHERE image_url LIKE ?`, [oldPrefix, profile.storagePublicUrl, `%${oldPrefix}%`]);
            const [mRes2] = await connection.execute(`UPDATE messages SET video_url = REPLACE(video_url, ?, ?) WHERE video_url LIKE ?`, [oldPrefix, profile.storagePublicUrl, `%${oldPrefix}%`]);
            const [mRes3] = await connection.execute(`UPDATE messages SET voice_url = REPLACE(voice_url, ?, ?) WHERE voice_url LIKE ?`, [oldPrefix, profile.storagePublicUrl, `%${oldPrefix}%`]);
            const messageUpdates = (mRes1.affectedRows || 0) + (mRes2.affectedRows || 0) + (mRes3.affectedRows || 0);
            if (messageUpdates > 0)
                console.log(`      • messages: updated ${messageUpdates} fields`);
            totalReplacements += (userUpdates + pRes1.affectedRows + cRes.affectedRows + eRes.affectedRows + storyUpdates + messageUpdates);
        }
        await connection.end();
        console.log(`\n🎉 Environment synchronization complete!`);
        console.log(`   Everything in backend-hono, Flutter, and MySQL is now configured for [${targetProfileKey.toUpperCase()}].\n`);
    }
    catch (dbErr) {
        console.warn(`\n⚠️ Note: Could not connect to MySQL at ${profile.databaseUrl.replace(/:[^:@]+@/, ':****@')}: ${dbErr.message}`);
        console.log(`   Config files (.env) have been updated successfully! Once MySQL is online at this address, re-run:`);
        console.log(`   npm run switch-env ${targetProfileKey}\n`);
    }
}
main().catch((err) => {
    console.error('Fatal error during environment switch:', err);
    process.exit(1);
});
