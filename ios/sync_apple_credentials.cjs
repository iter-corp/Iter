const https = require('https');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const keyId = process.env.APP_STORE_CONNECT_KEY_ID;
const issuerId = process.env.APP_STORE_CONNECT_ISSUER_ID;
let privateKey = process.env.APP_STORE_CONNECT_PRIVATE_KEY;

if (!keyId || !issuerId || !privateKey) {
  console.log('App Store Connect API credentials not fully configured in environment.');
  process.exit(0);
}

// Clean up private key formatting if necessary
if (!privateKey.includes('-----BEGIN PRIVATE KEY-----')) {
  privateKey = `-----BEGIN PRIVATE KEY-----\n${privateKey.trim()}\n-----END PRIVATE KEY-----`;
}

function generateToken() {
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: keyId, typ: 'JWT' })).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const payload = Buffer.from(JSON.stringify({ iss: issuerId, exp: now + 1200, aud: 'appstoreconnect-v1' })).toString('base64url');
  const sign = crypto.createSign('SHA256');
  sign.update(`${header}.${payload}`);
  const signature = sign.sign({ key: privateKey, dsaEncoding: 'ieee-p1363' }, 'base64url');
  return `${header}.${payload}.${signature}`;
}

function apiRequest(endpoint) {
  return new Promise((resolve, reject) => {
    const token = generateToken();
    const options = {
      hostname: 'api.appstoreconnect.apple.com',
      path: endpoint,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Accept': 'application/json',
        'User-Agent': 'Iter-CI/1.0'
      }
    };

    https.get(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            resolve(body);
          }
        } else {
          reject(new Error(`API ${endpoint} failed with status ${res.statusCode}: ${body}`));
        }
      });
    }).on('error', reject);
  });
}

async function sync() {
  console.log('=== App Store Connect API Synchronization ===');
  console.log(`Key ID: ${keyId}`);
  console.log(`Issuer ID: ${issuerId}`);

  const runnerTemp = process.env.RUNNER_TEMP || '/tmp';
  const keychainPath = `${runnerTemp}/app-signing.keychain-db`;
  const homeDir = process.env.HOME || process.env.USERPROFILE || '';
  const profilesDir = path.join(homeDir, 'Library/MobileDevice/Provisioning Profiles');
  fs.mkdirSync(profilesDir, { recursive: true });

  // 1. Fetch Bundle IDs
  try {
    const bundleRes = await apiRequest('/v1/bundleIds?limit=50');
    console.log(`Found ${bundleRes.data?.length || 0} registered Bundle IDs:`);
    for (const b of (bundleRes.data || [])) {
      console.log(`  - ${b.attributes.identifier} (ID: ${b.id}, Name: ${b.attributes.name})`);
    }
  } catch (e) {
    console.warn(`Warning fetching bundle IDs: ${e.message}`);
  }

  // 2. Fetch Certificates
  try {
    const certsRes = await apiRequest('/v1/certificates?limit=50');
    console.log(`Found ${certsRes.data?.length || 0} certificates on Apple Developer portal:`);
    for (const c of (certsRes.data || [])) {
      console.log(`  - Type: ${c.attributes.certificateType}, Name: ${c.attributes.name}, Serial: ${c.attributes.serialNumber}, Exp: ${c.attributes.expirationDate}`);
      if (c.attributes.certificateContent) {
        const certFile = path.join(runnerTemp, `${c.id}.cer`);
        fs.writeFileSync(certFile, Buffer.from(c.attributes.certificateContent, 'base64'));
        if (fs.existsSync(keychainPath)) {
          try {
            execSync(`security import "${certFile}" -k "${keychainPath}" -A 2>/dev/null || true`);
          } catch (_) {}
        }
      }
    }
  } catch (e) {
    console.warn(`Warning fetching certificates: ${e.message}`);
  }

  // 3. Fetch Provisioning Profiles
  try {
    const profilesRes = await apiRequest('/v1/profiles?include=bundleId&limit=100');
    console.log(`Found ${profilesRes.data?.length || 0} provisioning profiles on Apple Developer portal:`);
    
    let matchedProfile = null;
    for (const p of (profilesRes.data || [])) {
      const pName = p.attributes.name;
      const pType = p.attributes.profileType;
      const pState = p.attributes.profileState;
      const pUuid = p.attributes.uuid;
      console.log(`  - Profile: "${pName}" [${pType}] State: ${pState}, UUID: ${pUuid}`);

      if (pState === 'ACTIVE' && p.attributes.profileContent) {
        const buf = Buffer.from(p.attributes.profileContent, 'base64');
        const targetPath = path.join(profilesDir, `${pUuid}.mobileprovision`);
        fs.writeFileSync(targetPath, buf);

        // Check if this profile matches com.iter.ai or is an App Store profile
        if (pType === 'IOS_APP_STORE' || pName.toLowerCase().includes('iter') || pName.toLowerCase().includes('distribution')) {
          if (!matchedProfile || pName.toLowerCase().includes('iter')) {
            matchedProfile = p;
            fs.writeFileSync(path.join(profilesDir, 'profile.mobileprovision'), buf);
          }
        }
      }
    }

    if (matchedProfile) {
      const pName = matchedProfile.attributes.name;
      const pUuid = matchedProfile.attributes.uuid;
      console.log(`\n>>> Selected Active App Store Profile: "${pName}" (${pUuid})`);

      // Update ios/Flutter/Release.xcconfig
      const xcconfigPath = 'ios/Flutter/Release.xcconfig';
      if (fs.existsSync(xcconfigPath)) {
        let content = fs.readFileSync(xcconfigPath, 'utf8');
        content += `\nPROVISIONING_PROFILE_SPECIFIER = ${pName}\nPROVISIONING_PROFILE = ${pUuid}\n`;
        fs.writeFileSync(xcconfigPath, content);
        console.log('Updated ios/Flutter/Release.xcconfig with profile specifier.');
      }

      // Update ios/ExportOptions.plist
      const exportPlistPath = 'ios/ExportOptions.plist';
      if (fs.existsSync(exportPlistPath)) {
        try {
          execSync(`/usr/libexec/PlistBuddy -c "Add :signingStyle string manual" "${exportPlistPath}" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :signingStyle manual" "${exportPlistPath}" 2>/dev/null || true`);
          execSync(`/usr/libexec/PlistBuddy -c "Add :provisioningProfiles dict" "${exportPlistPath}" 2>/dev/null || true`);
          execSync(`/usr/libexec/PlistBuddy -c "Add :provisioningProfiles:com.iter.ai string ${pName}" "${exportPlistPath}" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :provisioningProfiles:com.iter.ai ${pName}" "${exportPlistPath}" 2>/dev/null || true`);
          console.log(`Updated ios/ExportOptions.plist with provisioning profile "${pName}".`);
        } catch (err) {
          console.warn(`Notice updating ExportOptions.plist: ${err.message}`);
        }
      }
    } else {
      console.log('No specific com.iter.ai active App Store profile found among existing profiles.');
    }
  } catch (e) {
    console.error(`Error fetching provisioning profiles: ${e.message}`);
  }

  console.log('=== Synchronization Complete ===\n');
}

sync().catch(err => {
  console.error('Fatal sync error:', err);
  process.exit(1);
});
