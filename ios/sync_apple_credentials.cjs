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

function apiRequest(endpoint, method = 'GET', data = null) {
  return new Promise((resolve, reject) => {
    const token = generateToken();
    const headers = {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/json',
      'User-Agent': 'Iter-CI/1.0'
    };
    let payload = null;
    if (data) {
      payload = JSON.stringify(data);
      headers['Content-Type'] = 'application/json';
      headers['Content-Length'] = Buffer.byteLength(payload);
    }
    const options = {
      hostname: 'api.appstoreconnect.apple.com',
      path: endpoint,
      method: method,
      headers: headers
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          if (!body || body.trim() === '') {
            resolve({});
            return;
          }
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            resolve(body);
          }
        } else {
          reject(new Error(`API ${method} ${endpoint} failed with status ${res.statusCode}: ${body}`));
        }
      });
    });
    req.on('error', reject);
    if (payload) {
      req.write(payload);
    }
    req.end();
  });
}

async function sync() {
  console.log('=== App Store Connect API Synchronization ===');
  console.log(`Key ID: ${keyId}`);
  console.log(`Issuer ID: ${issuerId}`);

  const runnerTemp = process.env.RUNNER_TEMP || '/tmp';
  const keychainPath = `${runnerTemp}/app-signing.keychain-db`;
  const keychainPass = process.env.KEYCHAIN_PASSWORD || 'temporary_runner_keychain_pass';
  const homeDir = process.env.HOME || process.env.USERPROFILE || '';
  const profilesDir = path.join(homeDir, 'Library/MobileDevice/Provisioning Profiles');
  fs.mkdirSync(profilesDir, { recursive: true });

  // 1. Fetch Bundle IDs
  let bundleList = [];
  try {
    const bundleRes = await apiRequest('/v1/bundleIds?limit=50');
    bundleList = bundleRes.data || [];
    console.log(`Found ${bundleList.length} registered Bundle IDs:`);
    for (const b of bundleList) {
      console.log(`  - ${b.attributes.identifier} (ID: ${b.id}, Name: ${b.attributes.name})`);
    }
  } catch (e) {
    console.warn(`Warning fetching bundle IDs: ${e.message}`);
  }

  const targetBundleId = process.env.APP_BUNDLE_ID || 'com.iter.ai';
  const iterBundle = bundleList.find(b => b.attributes.identifier === targetBundleId);

  // 2. Fetch Certificates
  let certList = [];
  try {
    const certsRes = await apiRequest('/v1/certificates?limit=50');
    certList = certsRes.data || [];
    console.log(`Found ${certList.length} certificates on Apple Developer portal:`);
    for (const c of certList) {
      console.log(`  - Type: ${c.attributes.certificateType}, Name: ${c.attributes.name}, Serial: ${c.attributes.serialNumber}, ID: ${c.id}`);
    }
  } catch (e) {
    console.warn(`Warning fetching certificates: ${e.message}`);
  }

  // Check if keychain has a distribution private key
  let hasDistPrivateKey = false;
  try {
    const idCheck = execSync(`security find-identity -v -p codesigning "${keychainPath}" 2>/dev/null || true`).toString();
    if (idCheck.includes('Apple Distribution')) {
      hasDistPrivateKey = true;
    }
  } catch (_) {}

  let distCert = certList.find(c =>
    c.attributes.certificateType === 'DISTRIBUTION' ||
    c.attributes.certificateType === 'IOS_DISTRIBUTION'
  );

  // If there is an existing distribution certificate on Apple portal, but this runner does not possess its private key:
  // Revoke it via App Store Connect API so a new one with a locally-held private key can be cleanly generated.
  if (!hasDistPrivateKey && distCert) {
    console.log(`\nExisting Distribution certificate ${distCert.id} found without local private key in keychain.`);
    console.log(`Revoking orphan certificate ${distCert.id} to generate a fresh pair with matching private key...`);
    try {
      await apiRequest(`/v1/certificates/${distCert.id}`, 'DELETE');
      console.log(`Successfully revoked certificate ${distCert.id}.`);
      distCert = null;
    } catch (err) {
      console.warn(`Could not revoke certificate: ${err.message}`);
    }
  }

  // If no distribution cert with private key exists, generate one
  if (!distCert) {
    console.log('\nGenerating RSA 2048-bit key and CSR for Apple Distribution certificate...');
    try {
      const keyPath = path.join(runnerTemp, 'dist_key.pem');
      const csrPath = path.join(runnerTemp, 'dist_csr.pem');
      execSync(`openssl req -new -newkey rsa:2048 -nodes -keyout "${keyPath}" -out "${csrPath}" -subj "/CN=Apple Distribution: Iter/C=US"`);
      const csrContent = fs.readFileSync(csrPath, 'utf8').trim();

      console.log('Submitting CSR to App Store Connect API...');
      const newCertRes = await apiRequest('/v1/certificates', 'POST', {
        data: {
          type: 'certificates',
          attributes: {
            certificateType: 'DISTRIBUTION',
            csrContent: csrContent
          }
        }
      });
      distCert = newCertRes.data;
      console.log(`Successfully created Apple Distribution certificate: ID ${distCert.id}, Serial: ${distCert.attributes.serialNumber}`);

      // Apple returns DER formatted certificate base64. Convert DER -> PEM -> PKCS#12 (.p12)
      const cerDerPath = path.join(runnerTemp, 'dist_cert.cer');
      const cerPemPath = path.join(runnerTemp, 'dist_cert.pem');
      const p12Path = path.join(runnerTemp, 'dist.p12');

      fs.writeFileSync(cerDerPath, Buffer.from(distCert.attributes.certificateContent, 'base64'));
      execSync(`openssl x509 -inform DER -in "${cerDerPath}" -out "${cerPemPath}"`);
      execSync(`openssl pkcs12 -export -inkey "${keyPath}" -in "${cerPemPath}" -out "${p12Path}" -passout "pass:${keychainPass}"`);
      execSync(`security import "${p12Path}" -k "${keychainPath}" -P "${keychainPass}" -A -T /usr/bin/codesign`);
      execSync(`security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${keychainPass}" "${keychainPath}" || true`);
      console.log('Successfully imported Apple Distribution certificate and private key into build keychain.');
    } catch (err) {
      console.error(`Failed to generate distribution certificate: ${err.message}`);
    }
  } else {
    console.log(`Active Distribution certificate in use: ID ${distCert.id}`);
  }

  // 3. Fetch Provisioning Profiles
  let profileList = [];
  try {
    const profilesRes = await apiRequest('/v1/profiles?include=bundleId,certificates&limit=100');
    profileList = profilesRes.data || [];
    console.log(`\nFound ${profileList.length} provisioning profiles on Apple Developer portal:`);
    for (const p of profileList) {
      console.log(`  - Profile: "${p.attributes.name}" [${p.attributes.profileType}] State: ${p.attributes.profileState}, UUID: ${p.attributes.uuid}`);
    }
  } catch (e) {
    console.error(`Error fetching provisioning profiles: ${e.message}`);
  }

  // Check if existing profile matches current distCert
  let matchedProfile = null;
  if (distCert) {
    for (const p of profileList) {
      const isForOurBundle = iterBundle && p.relationships?.bundleId?.data?.id === iterBundle.id;
      if (p.attributes.profileState === 'ACTIVE' && p.attributes.profileType === 'IOS_APP_STORE' && isForOurBundle) {
        const hasOurCert = (p.relationships?.certificates?.data || []).some(c => c.id === distCert.id);
        if (hasOurCert) {
          matchedProfile = p;
          break;
        } else {
          console.log(`Profile "${p.attributes.name}" is linked to an older certificate. Removing to update...`);
          try {
            await apiRequest(`/v1/profiles/${p.id}`, 'DELETE');
          } catch (_) {}
        }
      }
    }
  }

  // If no matching profile exists, create an App Store Provisioning Profile for targetBundleId
  if (!matchedProfile && iterBundle && distCert) {
    console.log(`\nCreating new App Store provisioning profile for ${targetBundleId} with Certificate ${distCert.id}...`);
    try {
      const profileName = `${targetBundleId === 'com.iter.ai.dev' ? 'IterDev' : 'Iter'} AppStore Distribution ${Date.now()}`;
      const newProfileRes = await apiRequest('/v1/profiles', 'POST', {
        data: {
          type: 'profiles',
          attributes: {
            name: profileName,
            profileType: 'IOS_APP_STORE'
          },
          relationships: {
            bundleId: {
              data: {
                type: 'bundleIds',
                id: iterBundle.id
              }
            },
            certificates: {
              data: [
                {
                  type: 'certificates',
                  id: distCert.id
                }
              ]
            }
          }
        }
      });
      matchedProfile = newProfileRes.data;
      console.log(`Successfully created App Store provisioning profile: "${matchedProfile.attributes.name}" (${matchedProfile.attributes.uuid})`);
    } catch (err) {
      console.error(`Failed to create App Store provisioning profile: ${err.message}`);
    }
  }

  // 4. Install Profile & Configure Build Settings
  if (matchedProfile && matchedProfile.attributes.profileContent) {
    const buf = Buffer.from(matchedProfile.attributes.profileContent, 'base64');
    const targetPath = path.join(profilesDir, `${matchedProfile.attributes.uuid}.mobileprovision`);
    fs.writeFileSync(targetPath, buf);
    fs.writeFileSync(path.join(profilesDir, 'profile.mobileprovision'), buf);
    console.log(`Installed provisioning profile to ${targetPath}`);

    const pName = matchedProfile.attributes.name;
    const pUuid = matchedProfile.attributes.uuid;

    // Update ios/Flutter/Release.xcconfig
    const xcconfigPath = 'ios/Flutter/Release.xcconfig';
    if (fs.existsSync(xcconfigPath)) {
      let content = fs.readFileSync(xcconfigPath, 'utf8');
      content += `\nCODE_SIGN_STYLE = Manual\nCODE_SIGN_IDENTITY = Apple Distribution\nCODE_SIGN_IDENTITY[sdk=iphoneos*] = Apple Distribution\nPROVISIONING_PROFILE_SPECIFIER = ${pName}\nPROVISIONING_PROFILE = ${pUuid}\nDEVELOPMENT_TEAM = WAC85HB79P\n`;
      fs.writeFileSync(xcconfigPath, content);
      console.log(`Updated ios/Flutter/Release.xcconfig with manual signing configuration: ${pName} (${pUuid})`);
    }

    // Update ios/ExportOptions.plist
    const exportPlistPath = 'ios/ExportOptions.plist';
    if (fs.existsSync(exportPlistPath)) {
      try {
        execSync(`/usr/libexec/PlistBuddy -c "Add :signingStyle string manual" "${exportPlistPath}" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :signingStyle manual" "${exportPlistPath}" 2>/dev/null || true`);
        execSync(`/usr/libexec/PlistBuddy -c "Add :provisioningProfiles dict" "${exportPlistPath}" 2>/dev/null || true`);
        execSync(`/usr/libexec/PlistBuddy -c "Add :provisioningProfiles:${targetBundleId} string ${pName}" "${exportPlistPath}" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :provisioningProfiles:${targetBundleId} ${pName}" "${exportPlistPath}" 2>/dev/null || true`);
        console.log(`Updated ios/ExportOptions.plist with profile mapping ${targetBundleId} -> ${pName}`);
      } catch (err) {
        console.warn(`Notice updating ExportOptions.plist: ${err.message}`);
      }
    }
  }

  // Print verified code signing identities
  console.log('\nVerified code signing identities in build keychain:');
  try {
    const ids = execSync(`security find-identity -v -p codesigning "${keychainPath}" 2>/dev/null || true`).toString();
    console.log(ids);
  } catch (err) {
    console.warn('Could not verify identities:', err.message);
  }

  console.log('=== Synchronization Complete ===\n');
}

sync().catch(err => {
  console.error('Fatal sync error:', err);
  process.exit(1);
});
