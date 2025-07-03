/** @type {import('next').NextConfig} */
const nextConfig = {
    experimental: {
        after: true
    },
    images: {
        remotePatterns: [
            {
                hostname: 'localhost'
            },
            {
                hostname: 'host.docker.internal'
            },
            // ✅ Adicionado o IP público da EC2:
            {
                hostname: '54.235.157.122'
            }
        ]
    }
};

export default nextConfig;
