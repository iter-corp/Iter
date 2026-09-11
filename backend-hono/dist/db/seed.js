import { db, poolConnection } from './index.js';
import { appConfigs, users, sduiScreens, dynamicEnums, apiKeys } from './schema/index.js';
import bcrypt from 'bcryptjs';
import { env } from '../config/env.js';
export async function seed() {
    console.log('🌱 Starting database seed on MySQL...');
    try {
        // 1. Seed default appConfigs
        try {
            await db.insert(appConfigs).ignore().values({
                id: 'app',
                storiesEnabled: true,
                repostsEnabled: true,
                translateEnabled: true,
                maintenanceMode: false,
                maintenanceMessage: 'Iter is temporarily under scheduled maintenance. Please check back shortly.',
                minAppVersion: '1.0.0',
                announcement: 'Welcome to Iter! Connect, explore, and share with your community.',
                contactEmail: 'support@iter.app',
                iosAppStoreUrl: 'https://apps.apple.com/app/iter',
                androidPlayStoreUrl: 'https://play.google.com/store/apps/details?id=com.iter.app',
                eventTypes: [
                    'Scholarship', 'Internship', 'Research', 'Conference',
                    'Summer Program', 'Competition', 'Leadership', 'Youth Summit', 'other'
                ],
                profileProfessionOptions: [
                    'Student', 'Software Engineer', 'Designer', 'Doctor', 'Teacher',
                    'Lawyer', 'Accountant', 'Researcher', 'Entrepreneur', 'Other'
                ],
                profileFieldOptions: [
                    'Computer Science', 'Medicine', 'Engineering', 'Business',
                    'Arts & Humanities', 'Law', 'Natural Sciences', 'Social Sciences', 'Other'
                ],
                profileAcademicLevelOptions: [
                    'High School', 'Bachelor', 'Master', 'PhD', 'Self-taught', 'Other'
                ],
                profileGoalOptions: [
                    'Internships', 'Scholarships', 'Conferences', 'Research', 'Networking', 'Local events'
                ],
                profanityWordsEn: [
                    'asshole', 'bastard', 'bitch', 'bullshit', 'damn', 'dick', 'fuck', 'fucker',
                    'fucking', 'hell', 'motherfucker', 'piss', 'prick', 'shit', 'slut', 'whore'
                ],
                featureFlags: {
                    'enable_ai_translation': true,
                    'enable_polls': true,
                    'enable_event_registration': true,
                    'enable_voice_notes': true,
                    'enable_stickers': true,
                    'enable_location_pin': true,
                },
            });
            console.log('✅ App configs seeded');
        }
        catch (e) {
            console.log('ℹ️ App configs already exists or skipped');
        }
        // 2. Seed initial Admin User
        try {
            const adminPasswordHash = await bcrypt.hash('Admin@123456', 10);
            await db.insert(users).ignore().values({
                id: 'admin_initial_root',
                email: 'admin@iter.app',
                emailVerified: true,
                passwordHash: adminPasswordHash,
                username: 'admin',
                usernameLower: 'admin',
                handle: '@admin',
                bio: 'Official Iter System Administrator',
                role: 'admin',
                isPrivate: false,
                appIntroSeen: true,
            });
            console.log('✅ Super Admin user seeded: admin@iter.app / Admin@123456');
        }
        catch (e) {
            console.log('ℹ️ Admin user already exists or skipped');
        }
        // 3. Seed Server-Driven UI (SDUI) Screens
        try {
            await db.insert(sduiScreens).ignore().values({
                id: 'home_top',
                title: 'Home Feed Spotlight',
                description: 'Dynamic banner displayed at the top of the main home feed',
                version: 1,
                active: true,
                layout: {
                    type: 'banner',
                    blocks: [
                        {
                            id: 'welcome_banner_1',
                            type: 'announcement',
                            title: 'Welcome to Iter',
                            subtitle: 'Discover opportunities, discussions, and student communities worldwide.',
                            backgroundColor: '#1E1E2E',
                            textColor: '#FFFFFF',
                            action: {
                                type: 'navigate',
                                target: '/explore',
                            },
                        }
                    ],
                },
            });
            console.log('✅ Server-Driven UI screens seeded');
        }
        catch (e) {
            console.log('ℹ️ SDUI screen already exists or skipped');
        }
        // 4. Seed Dynamic Enums
        try {
            await db.insert(dynamicEnums).ignore().values({
                id: 'report_reasons',
                name: 'Content Report Reasons',
                items: [
                    { label: 'Spam or Misleading', value: 'spam' },
                    { label: 'Harassment or Bullying', value: 'harassment' },
                    { label: 'Hate Speech', value: 'hate_speech' },
                    { label: 'Inappropriate Content', value: 'inappropriate' },
                    { label: 'Copyright Violation', value: 'copyright' },
                    { label: 'Other', value: 'other' },
                ],
            });
            console.log('✅ Dynamic enums seeded');
        }
        catch (e) {
            console.log('ℹ️ Dynamic enums already exists or skipped');
        }
        // 5. Seed API Keys (if provided in env)
        if (env.GEMINI_API_KEY) {
            try {
                await db.insert(apiKeys).ignore().values({
                    id: 'api_key_gemini_primary',
                    provider: 'gemini',
                    key: env.GEMINI_API_KEY,
                    active: true,
                    priority: 1,
                    statusMessage: 'Operational',
                });
                console.log('✅ API keys initialized');
            }
            catch (e) {
                console.log('ℹ️ API keys skipped');
            }
        }
        console.log('🎉 Database seeding completed successfully!');
    }
    catch (error) {
        console.error('❌ Seeding failed:', error);
    }
    finally {
        await poolConnection.end();
    }
}
if (process.argv[1]?.includes('seed.ts')) {
    seed().then(() => process.exit(0));
}
