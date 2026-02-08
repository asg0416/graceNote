import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://admin.gracenote.io.kr"),
  title: "Grace Note Admin",
  description: "Grace Note 교회 관리 시스템 - 효율적인 성도 관리를 위해",
  icons: {
    icon: "/favicon.png",
  },
  openGraph: {
    title: "Grace Note Admin",
    description: "Grace Note 교회 관리 시스템 - 효율적인 성도 관리를 위해",
    url: "https://admin.gracenote.io.kr",
    siteName: "Grace Note Admin",
    images: [
      {
        url: "/ogImg.png?v=2",
        width: 1200,
        height: 630,
      },
    ],
    locale: "ko_KR",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Grace Note Admin",
    description: "Grace Note 교회 관리 시스템 - 효율적인 성도 관리를 위해",
    images: ["/ogImg.png?v=2"],
  },
};

import { ThemeProvider } from "@/components/ThemeProvider";
import SidebarWrapper from "@/components/SidebarWrapper";

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ko" suppressHydrationWarning>
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased font-sans transition-colors duration-300`}
      >
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          disableTransitionOnChange
        >
          <SidebarWrapper>{children}</SidebarWrapper>

          {/* DEV MODE INDICATOR */}
          {process.env.NEXT_PUBLIC_SUPABASE_URL?.includes('eftdf') && (
            <div className="fixed bottom-4 right-4 bg-red-500/90 text-white px-4 py-1.5 rounded-full text-sm font-bold shadow-lg z-50 pointer-events-none border-2 border-white/20 animate-pulse">
              🚧 DEV MODE 🚧
            </div>
          )}
        </ThemeProvider>
      </body>
    </html>
  );
}
