namespace Library
{
    public static class typ
    {
        public static T def<T>()
        {
            return default(T);
        }

        public static T to<T>(object it)
        {
            return (T)it;
        }

        public static bool @is<T>(object it)
        {
            return it is T;
        }

        public static T @as<T>(object it) where T : class
        {
            return it as T;
        }
    }
}
