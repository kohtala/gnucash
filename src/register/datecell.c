/********************************************************************\
 * This program is free software; you can redistribute it and/or    *
 * modify it under the terms of the GNU General Public License as   *
 * published by the Free Software Foundation; either version 2 of   *
 * the License, or (at your option) any later version.              *
 *                                                                  *
 * This program is distributed in the hope that it will be useful,  *
 * but WITHOUT ANY WARRANTY; without even the implied warranty of   *
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the    *
 * GNU General Public License for more details.                     *
 *                                                                  *
 * You should have received a copy of the GNU General Public License*
 * along with this program; if not, contact:                        *
 *                                                                  *
 * Free Software Foundation           Voice:  +1-617-542-5942       *
 * 59 Temple Place - Suite 330        Fax:    +1-617-542-2652       *
 * Boston, MA  02111-1307,  USA       gnu@gnu.org                   *
 *                                                                  *
\********************************************************************/

/*
 * FILE:
 * datecell.c
 *
 * FUNCTION:
 * implements a gui-independent date handling cell.
 *
 * HISTORY:
 * Copyright (C) 1997 Robin D. Clark
 * Copyright (c) 1998, 1999, 2000 Linas Vepstas
 * Copyright (c) 2000 Dave Peticolas
 */

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "date.h"  /* hack alert -- don't include from engine directory */
#include "util.h"

#include "basiccell.h"
#include "datecell.h"


static void setDateCellValue (BasicCell *, const char *);

/* This static indicates the debugging module that this .o belongs to.  */
static short module = MOD_REGISTER;


/* ================================================ */

static void
xaccParseDate (struct tm *parsed, const char * datestr)
{
   int iday, imonth, iyear;

   if (!parsed) return;
   if (!datestr) return;

   scanDate(datestr, &iday, &imonth, &iyear);

   parsed->tm_mday = iday;
   parsed->tm_mon = imonth-1;
   parsed->tm_year = iyear-1900;
}

/* ================================================ */

static char *
DateCellHelpValue(BasicCell *bcell)
{
  DateCell *cell = (DateCell *) bcell;

  if ((bcell->value != NULL) && (bcell->value[0] != 0))
  {
    char string[1024];
    struct tm time;

    memset(&time, 0, sizeof(time));

    if (bcell->value != NULL)
      xaccParseDate (&time, bcell->value);
    else
    {
      time.tm_mday = cell->date.tm_mday;
      time.tm_mon  = cell->date.tm_mon;
      time.tm_year = cell->date.tm_year;
    }

    xaccValidateDate(&time);
    mktime(&time);

    strftime(string, sizeof(string), "%A %d %B %Y", &time);

    return g_strdup(string);
  }

  if (bcell->blank_help != NULL)
    return g_strdup(bcell->blank_help);

  return NULL;
}

/* ================================================ */

/* This code should be kept in sync with src/gnome/gnc-dateedit.c */
static void
DateMV (BasicCell *_cell, 
        const char *change, 
        const char *newval,
        int *cursor_position,
        int *start_selection,
        int *end_selection)
{
   DateCell *cell = (DateCell *) _cell;
   gboolean accept = FALSE;
   struct tm *date;
   char buff[30];

   /* if user hit backspace, accept the change */
   if (change == NULL) accept = TRUE;
   else if ('\0' == change[0]) accept = TRUE;
   else
   {
      int i, count = 0;
      char separator = dateSeparator();
      gboolean ok = TRUE;

      for (i = 0; '\0' != change[i]; i++)
      {
        /* accept only numbers or a date separator. Note that the
         * separator of '-' (for DATE_FORMAT_ISO) takes precedence
         * over the accelerator below! */
        if (!isdigit(change[i]) && (separator != change[i]))
          ok = FALSE;

        if (separator == change[i])
          count++;
      }

      for (i=0; '\0' != _cell->value[i]; i++)
        if (separator == _cell->value[i])
          count++;

      if (2 < count)
        ok = FALSE;

      if (ok)
        accept = TRUE;
   }

   /* keep a copy of the new value */
   if (accept) {
      g_free (cell->cell.value);
      cell->cell.value = g_strdup (newval);
      xaccParseDate (&(cell->date), newval);
      return;
   }

   /* otherwise, maybe its an accelerator key. */
   if (strlen(change) != 1)
     return;

   date = &(cell->date);

   /* handle accelerator keys */
   switch (change[0]) {
      case '+':
      case '=':
         /* increment day */
         date->tm_mday ++;
         break;

      case '_':
      case '-':
         /* decrement day */
         date->tm_mday --;
         break;

      case '}':
      case ']':
         /* increment month */
         date->tm_mon ++;
         break;

      case '{':
      case '[':
         /* decrement month */
         date->tm_mon --;
         break;

      case 'M':
      case 'm':
         /* beginning of month */
         date->tm_mday = 1;
         break;

      case 'H':
      case 'h':
         /* end of month */
         date->tm_mon ++;
         date->tm_mday = 0;
         break;

      case 'Y':
      case 'y':
         /* beginning of year */
         date->tm_mday = 1;
         date->tm_mon = 0;
         break;

      case 'R':
      case 'r':
         /* end of year */
         date->tm_mday = 31;
         date->tm_mon = 11;
         break;

      case 'T':
      case 't': {
         /* today */
         time_t secs;
         struct tm *now;

         time (&secs);
         now = localtime (&secs);
         *date = *now;
         break;
      }

      default:
         /* reject other changes */
         return;
   }

   xaccValidateDate (date);

   printDate (buff, date->tm_mday, date->tm_mon+1, date->tm_year+1900);

   g_free (cell->cell.value);
   cell->cell.value = g_strdup (buff);
}

/* ================================================ */

void
xaccCommitDateCell (DateCell *cell)
{
   char buff[30];

   if (!cell) return;

   ENTER ("value is %s \n", cell->cell.value);

   xaccParseDate (&(cell->date), cell->cell.value);
   printDate (buff, cell->date.tm_mday, 
                    cell->date.tm_mon+1, 
                    cell->date.tm_year+1900);

   g_free (cell->cell.value);
   cell->cell.value = g_strdup (buff);

   LEAVE ("value is %s \n", cell->cell.value);
}

/* ================================================ */

void
xaccDateCellGetDate (DateCell *cell, Timespec *ts)
{
  if (!cell || !ts) return;

  xaccParseDate (&(cell->date), cell->cell.value);

  ts->tv_sec = mktime(&cell->date);
  ts->tv_nsec = 0;
}

/* ================================================ */

DateCell *
xaccMallocDateCell (void)
{
   DateCell *cell;

   cell = g_new(DateCell, 1);

   xaccInitDateCell (cell);

   return cell;
}

/* ================================================ */

void
xaccInitDateCell (DateCell *cell)
{
   time_t secs;
   struct tm *now;
   char buff[30];

   xaccInitBasicCell (&(cell->cell));

   /* default value is today's date */
   time (&secs);
   now = localtime (&secs);
   cell->date = *now;
   printDate (buff, now->tm_mday, now->tm_mon+1, now->tm_year+1900);
 
   g_free (cell->cell.value);
   cell->cell.value = g_strdup (buff);
 
   cell->cell.modify_verify = DateMV;
   cell->cell.set_value = setDateCellValue;
   cell->cell.get_help_value = DateCellHelpValue;
}

/* ================================================ */

void
xaccDestroyDateCell (DateCell *cell)
{
   cell->date.tm_mday = 0;
   cell->date.tm_mon = 0;
   cell->date.tm_year = 0;

   xaccDestroyBasicCell (&(cell->cell));
}

/* ================================================ */

void 
xaccSetDateCellValue (DateCell *cell, int day, int mon, int year)
{
   struct tm dada;
   char buff[30];

   dada.tm_mday = day;
   dada.tm_mon = mon-1;
   dada.tm_year = year - 1900;

   xaccValidateDate (&dada);

   cell->date.tm_mday = dada.tm_mday;
   cell->date.tm_mon = dada.tm_mon;
   cell->date.tm_year = dada.tm_year;

   printDate (buff, dada.tm_mday, dada.tm_mon+1, dada.tm_year+1900);

   g_free (cell->cell.value);
   cell->cell.value = g_strdup (buff);
}

/* ================================================ */

void 
xaccSetDateCellValueSecs (DateCell *cell, time_t secs)
{
   char buff[30];
   struct tm * stm;

   stm = localtime (&secs);
   cell->date = *stm;

   printDate (buff, cell->date.tm_mday, 
                    cell->date.tm_mon+1, 
                    cell->date.tm_year+1900);

   g_free (cell->cell.value);
   cell->cell.value = g_strdup (buff);
}

/* ================================================ */

#define THIRTY_TWO_YEARS 0x3c30fc00LL

void 
xaccSetDateCellValueSecsL (DateCell *cell, long long secs)
{
   char buff[30];
   struct tm * stm;

   /* try to deal with dates earlier than December 1901 
    * or later than Jan 2038.  Note that xaccValidateDate
    * should be handling centential (non-) leap years.
    * The suffix LL indicates that consts should be handled
    * long long 64-bit consts.
    */
   if ((0x80000000LL > secs) || (0x7fffffffLL < secs)) 
   {
      int yrs;
      time_t rem;
      rem = secs % THIRTY_TWO_YEARS;
      yrs = secs / THIRTY_TWO_YEARS;
      stm = localtime (&rem);
      cell->date = *stm;
      cell->date.tm_year += 32 * yrs;
      xaccValidateDate (&(cell->date));
   } else {
      /* OK, time value is an unsigned 32-bit int */
      time_t sicko;
      sicko = secs;
      stm = localtime (&sicko);
      cell->date = *stm;
   }

   printDate (buff, cell->date.tm_mday, 
                    cell->date.tm_mon+1, 
                    cell->date.tm_year+1900);

   g_free (cell->cell.value);
   cell->cell.value = g_strdup (buff);
}

/* ================================================ */

static void 
setDateCellValue (BasicCell *_cell, const char *str)
{
   DateCell *cell = (DateCell *) _cell;
   char buff[30];

   xaccParseDate (&(cell->date), str);

   printDate (buff, cell->date.tm_mday, 
              cell->date.tm_mon+1, 
              cell->date.tm_year+1900);

   g_free (cell->cell.value);
   cell->cell.value = g_strdup (buff);
}

/* ============== END OF FILE ===================== */