namespace Library
{
    public static class lib
    {
        public static T[] arrOf<T>(params T[] item)
        {
            return item;
        }

        public static lst<T> lstOf<T>(params T[] item)
        {
            return new lst<T>(item);
        }

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
