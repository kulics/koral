//using System;

//namespace Library
//{
//    public class bl : iXsValue
//    {
//        private bool v;

//        public bl() { }

//        public bl(bool o) { v = o; }

//        public static implicit operator bl(bool it) => new bl(it);
//        public static implicit operator bool(bl it) => it.v;

//        public static bool operator ==(bl a, bl b) => a.v == b.v;
//        public static bool operator !=(bl a, bl b) => a.v != b.v;

//        public override bool Equals(object o)
//        {
//            if (o is bl b)
//            {
//                return v == b.v;
//            }
//            else
//            {
//                return false;
//            }
//        }

//        public bool Equals(bl b) => b != null && v == b.v;

//        public override int GetHashCode() => v.GetHashCode();

//        public TypeCode GetTypeCode() => v.GetTypeCode();

//        public string ToString(string format) => v.ToString();
//        public bool toValue() => v;
//        public object toAny() => v;
//    }
//}