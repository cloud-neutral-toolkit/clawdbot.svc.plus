export type ConsoleUser = {
    uuid: string;
    email: string;
    roles: string[];
    isAdmin: boolean;
};

export async function fetchConsoleUser(): Promise<ConsoleUser | null> {
    try {
        const res = await fetch('https://console.svc.plus/api/auth/session', {
            credentials: 'include'
        });
        if (!res.ok) return null;
        const data = await res.json();
        if (!data.user) return null;
        const user = data.user;
        // user.role is likely a string like 'admin' or 'operator'
        const isAdmin = user.role === 'admin' || user.role === 'administrator' || user.isAdmin;
        return {
            uuid: user.uuid || user.id,
            email: user.email,
            roles: user.role ? [user.role] : [],
            isAdmin: Boolean(isAdmin)
        };
    } catch (e) {
        console.warn("Failed to fetch console user", e);
        return null;
    }
}
