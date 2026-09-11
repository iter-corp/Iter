const path = require('path');
const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function seed() {
  console.log('🌱 Starting direct database seed on MySQL...');

  const dbHost = process.env.DB_HOST || '127.0.0.1';
  const dbPort = parseInt(process.env.DB_PORT || '3306', 10);
  const dbUser = process.env.DB_USER || 'u814384925_iter_user';
  const dbPassword = process.env.DB_PASSWORD || 'wkjBgrET&3AU8kqE';
  const dbName = process.env.DB_NAME || 'u814384925_iter_db';

  const connection = await mysql.createConnection({
    host: dbHost,
    port: dbPort,
    user: dbUser,
    password: dbPassword,
    database: dbName,
  });

  try {
    // 1. Seed appConfigs
    try {
      const eventTypes = JSON.stringify([
        'Scholarship', 'Internship', 'Research', 'Conference',
        'Summer Program', 'Competition', 'Leadership', 'Youth Summit', 'other'
      ]);
      const professionOptions = JSON.stringify([
        'Student', 'Software Engineer', 'Designer', 'Doctor', 'Teacher',
        'Lawyer', 'Accountant', 'Researcher', 'Entrepreneur', 'Other'
      ]);
      const fieldOptions = JSON.stringify([
        'Computer Science', 'Medicine', 'Engineering', 'Business',
        'Arts & Humanities', 'Law', 'Natural Sciences', 'Social Sciences', 'Other'
      ]);
      const academicLevelOptions = JSON.stringify([
        'High School', 'Bachelor', 'Master', 'PhD', 'Self-taught', 'Other'
      ]);
      const goalOptions = JSON.stringify([
        'Internships', 'Scholarships', 'Conferences', 'Research', 'Networking', 'Local events'
      ]);
      const profanityWords = JSON.stringify([
        'asshole', 'bastard', 'bitch', 'bullshit', 'damn', 'dick', 'fuck', 'fucker',
        'fucking', 'hell', 'motherfucker', 'piss', 'prick', 'shit', 'slut', 'whore'
      ]);
      const featureFlags = JSON.stringify({
        'enable_ai_translation': true,
        'enable_polls': true,
        'enable_event_registration': true,
        'enable_voice_notes': true,
        'enable_stickers': true,
        'enable_location_pin': true,
      });

      await connection.query(`
        INSERT IGNORE INTO \`app_configs\` (
          \`id\`, \`stories_enabled\`, \`reposts_enabled\`, \`translate_enabled\`,
          \`maintenance_mode\`, \`maintenance_message\`, \`min_app_version\`,
          \`announcement\`, \`contact_email\`, \`ios_app_store_url\`, \`android_play_store_url\`,
          \`event_types\`, \`profile_profession_options\`, \`profile_field_options\`,
          \`profile_academic_level_options\`, \`profile_goal_options\`,
          \`profanity_words_en\`, \`feature_flags\`
        ) VALUES (
          'app', 1, 1, 1, 0,
          'Iter is temporarily under scheduled maintenance. Please check back shortly.',
          '1.0.0', 'Welcome to Iter! Connect, explore, and share with your community.',
          'support@iter.app', 'https://apps.apple.com/app/iter', 'https://play.google.com/store/apps/details?id=com.iter.app',
          ?, ?, ?, ?, ?, ?, ?
        )
      `, [eventTypes, professionOptions, fieldOptions, academicLevelOptions, goalOptions, profanityWords, featureFlags]);
      console.log('✅ App configs seeded');
    } catch (e) {
      console.log('ℹ️ App configs step note:', e.message);
    }

    // 2. Seed Super Admin
    try {
      const adminPasswordHash = await bcrypt.hash('Admin@123456', 10);
      await connection.query(`
        INSERT IGNORE INTO \`users\` (
          \`id\`, \`email\`, \`email_verified\`, \`password_hash\`,
          \`username\`, \`username_lower\`, \`handle\`, \`bio\`,
          \`role\`, \`is_private\`, \`app_intro_seen\`
        ) VALUES (
          'admin_initial_root', 'admin@iter.app', 1, ?,
          'admin', 'admin', '@admin', 'Official Iter System Administrator',
          'admin', 0, 1
        )
      `, [adminPasswordHash]);
      console.log('✅ Super Admin user seeded: admin@iter.app / Admin@123456');
    } catch (e) {
      console.log('ℹ️ Admin user step note:', e.message);
    }

    // 3. Seed SDUI Screen
    try {
      const layout = JSON.stringify({
        type: 'banner',
        blocks: [
          {
            id: 'welcome_banner_1',
            type: 'announcement',
            title: 'Welcome to Iter',
            subtitle: 'Discover opportunities, discussions, and student communities worldwide.',
            backgroundColor: '#1E1E2E',
            textColor: '#FFFFFF',
            action: { type: 'navigate', target: '/explore' }
          }
        ]
      });

      await connection.query(`
        INSERT IGNORE INTO \`sdui_screens\` (
          \`id\`, \`title\`, \`description\`, \`version\`, \`active\`, \`layout\`
        ) VALUES (
          'home_top', 'Home Feed Spotlight', 'Dynamic banner displayed at the top of the main home feed', 1, 1, ?
        )
      `, [layout]);
      console.log('✅ Server-Driven UI screens seeded');
    } catch (e) {
      console.log('ℹ️ SDUI screen step note:', e.message);
    }

    // 4. Seed Dynamic Enums
    try {
      const items = JSON.stringify([
        { label: 'Spam or Misleading', value: 'spam' },
        { label: 'Harassment or Bullying', value: 'harassment' },
        { label: 'Hate Speech', value: 'hate_speech' },
        { label: 'Inappropriate Content', value: 'inappropriate' },
        { label: 'Copyright Violation', value: 'copyright' },
        { label: 'Other', value: 'other' }
      ]);

      await connection.query(`
        INSERT IGNORE INTO \`dynamic_enums\` (
          \`id\`, \`name\`, \`items\`
        ) VALUES (
          'report_reasons', 'Content Report Reasons', ?
        )
      `, [items]);
      console.log('✅ Dynamic enums seeded');
    } catch (e) {
      console.log('ℹ️ Dynamic enums step note:', e.message);
    }

    // 5. Seed API keys from env if provided
    if (process.env.GEMINI_API_KEY) {
      try {
        await connection.query(`
          INSERT IGNORE INTO \`api_keys\` (
            \`id\`, \`provider\`, \`key\`, \`active\`, \`priority\`, \`status_message\`
          ) VALUES (
            'api_key_gemini_primary', 'gemini', ?, 1, 1, 'Operational'
          )
        `, [process.env.GEMINI_API_KEY]);
        console.log('✅ API keys initialized');
      } catch (e) {
        console.log('ℹ️ API keys step note:', e.message);
      }
    }

    console.log('🎉 Database seeding completed successfully!');
  } catch (error) {
    console.error('❌ Seeding failed:', error);
    process.exit(1);
  } finally {
    await connection.end();
  }
}

seed();
